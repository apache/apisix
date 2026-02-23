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

    $ENV{LIMIT_COUNT_KEY} = "remote_addr";
}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: modified limit-count.incoming, cost == 2
--- config
    location = /t {
        content_by_lua_block {
            local conf = {
                time_window = 60,
                count = 10,
                allow_degradation = false,
                key_type = "var",
                policy = "local",
                rejected_code = 503,
                show_limit_quota_header = true,
                key = "remote_addr"
            }
            local limit_count_local = require "apisix.plugins.limit-count.limit-count-local"
            local lim = limit_count_local.new("plugin-limit-count", 10, 60)
            local uri = ngx.var.uri
            for i = 1, 7 do
                local delay, err = lim:incoming(uri, true, conf, 2)
                if not delay then
                    ngx.say(err)
                else
                    local remaining = err
                    ngx.say("remaining: ", remaining)
                end
            end
        }
    }
--- request
    GET /t
--- response_body
remaining: 8
remaining: 6
remaining: 4
remaining: 2
remaining: 0
rejected
rejected



=== TEST 2: set route(id: 1) using environment variable for key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "$ENV://LIMIT_COUNT_KEY"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 3: up the limit with environment variable for key
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 4: customize rate limit headers by plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 10,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key_type": "var",
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            local code, meta_body = t('/apisix/admin/plugin_metadata/limit-count',
                 ngx.HTTP_PUT,
                 [[{
                        "limit_header":"APISIX-RATELIMIT-QUOTA",
                        "remaining_header":"APISIX-RATELIMIT-REMAINING",
                        "reset_header":"APISIX-RATELIMIT-RESET"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 5: check rate limit headers
--- request
GET /hello
--- response_headers_like
APISIX-RATELIMIT-QUOTA: 10
APISIX-RATELIMIT-REMAINING: 9
APISIX-RATELIMIT-RESET: \d+
