#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }

    $ENV{REDIS_HOST} = "127.0.0.1";
}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    my $port = $ENV{TEST_NGINX_SERVER_PORT};

    my $config = $block->config // <<_EOC_;
    location /access_root_dir {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn')
            if not res then
                ngx.log(ngx.ERR, err or "failed to request /limit_conn")
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            ngx.exit(res.status)
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            local status_map = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                local status_key = resp.status
                if status_map[status_key] then
                    status_map[status_key] = status_map[status_key] + 1
                else
                    status_map[status_key] = 1
                end
            end
            if status_map[200] then
                ngx.say("status:200, count:" .. status_map[200])
            end
            if status_map[503] then
                ngx.say("status:503, count:" .. status_map[503])
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route with redis_host via $ENV://
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/limit_conn",
                    "plugins": {
                        "limit-conn": {
                            "conn": 2,
                            "burst": 1,
                            "default_conn_delay": 0.1,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "$ENV://REDIS_HOST"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: verify limit-conn works with $ENV:// redis_host
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
status:200, count:3
status:503, count:7
