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
}

use t::APISIX;

my $travis_os_name = $ENV{TRAVIS_OS_NAME};
if ((defined $travis_os_name) && $travis_os_name eq "linux") {
    plan(skip_all =>
      "skip under Travis CI inux environment which doesn't work well with IPv6");
} else {
    plan 'no_plan';
}

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

add_block_preprocessor(sub {
    my $block = shift;
    $block->set_value("listen_ipv6", 1);
});

run_tests();

__DATA__

=== TEST 1: set route(two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1970": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 1
                                }
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 2: hit routes (two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.log(ngx.ERR, "It works")
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                ngx.log(ngx.ERR, "req ", i)
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ngx.log(ngx.ERR, "req ", i, " ", res.body)
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/Connection refused\) while connecting to upstream/
--- timeout: 10
