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

use t::APISIX 'no_plan';

no_long_string();
no_shuffle();
no_root_location();
log_level('info');

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

=== TEST 1: configure count/time_window and rules at same time
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
                                "time_window": 5,
                                "rejected_code": 503,
                                "key_type": "var",
                                "key": "remote_addr",
                                "rules": [
                                    {
                                        "count": 1,
                                        "time_window": 10,
                                        "key": "${http_company}"
                                    }
                                ]
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
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: value should match only one schema, but matches both schemas 1 and 2"}



=== TEST 2: configure multiple rules with same key
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
                                "rejected_code": 503,
                                "rules": [
                                    {
                                        "count": 5,
                                        "time_window": 10,
                                        "key": "${http_company}"
                                    },
                                    {
                                        "count": 8,
                                        "time_window": 20,
                                        "key": "${http_company}"
                                    }
                                ]
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
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: duplicate key '${http_company}' in rules"}



=== TEST 3: setup route with rules
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
                                "rejected_code": 503,
                                "rejected_msg" : "rejected",
                                "rules": [
                                    {
                                        "key": "${http_user}",
                                        "count": "${http_jack_count}",
                                        "time_window": 60
                                    },
                                    {
                                        "key": "${http_project}",
                                        "count": "${http_apisix_count}",
                                        "time_window": 60
                                    }
                                ]
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



=== TEST 4: no any rule matched
--- request
GET /hello
--- error_code: 500
--- error_log
failed to get rate limit rules



=== TEST 5: match user rule
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- more_headers
user: jack
jack-count: 2
--- error_code eval
[200, 200, 503]
--- response_body eval
["hello world\n", "hello world\n", "{\"error_msg\":\"rejected\"}\n"]



=== TEST 6: match project rule
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers
project: apisix
apisix-count: 3
--- error_code eval
[200, 200, 200, 503]
--- response_body eval
["hello world\n", "hello world\n", "hello world\n", "{\"error_msg\":\"rejected\"}\n"]



=== TEST 7: setup route with rules with variables with default values
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
                                "rejected_code": 503,
                                "rejected_msg" : "rejected",
                                "rules": [
                                    {
                                        "count": "${http_count ?? 2}",
                                        "time_window": "${http_tw ?? 5}",
                                        "key": "${remote_addr}"
                                    }
                                ]
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



=== TEST 8: rules with variables in count - default value
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]
--- response_body eval
["hello world\n", "hello world\n", "{\"error_msg\":\"rejected\"}\n"]



=== TEST 9: rules with variables in count - with header
--- setup
    ngx.sleep(5)
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers
count: 1
--- error_code eval
[200, 503]
--- response_body eval
["hello world\n", "{\"error_msg\":\"rejected\"}\n"]



=== TEST 10: rules with same key and custom headers
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
                                "rejected_code": 503,
                                "rejected_msg" : "rejected",
                                "show_limit_quota_header": true,
                                "rules": [
                                    {
                                        "count": 2,
                                        "time_window": 2,
                                        "key": "${remote_addr}_2s"
                                    },
                                    {
                                        "count": 3,
                                        "time_window": 5,
                                        "key": "${remote_addr}_5s"
                                    }
                                ]
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



=== TEST 11: test rules with same key
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 2, 1 do
                local res = httpc:request_uri(uri)
                if res.status ~= 200 then
                    ngx.say("first two requests failed, status: " .. res.status)
                    return
                end
            end

            -- req 3, rejected by rule 1
            res = httpc:request_uri(uri)
            if res.status ~= 503 then
                ngx.say("req 3 should be rejected by rule 1, but got status: ", res.status)
                return
            end

            ngx.sleep(2)

            -- req 4, after sleep
            res = httpc:request_uri(uri)
            if res.status ~= 200 then
                ngx.say("req 4 failed, status: ", res.status)
                return
            end

            -- req 5, rejected by rule 2
            res = httpc:request_uri(uri)
            if res.status ~= 503 then
                ngx.say("req 5 should be rejected by rule 2, but got status: ", res.status)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 12: setup route with header_prefix
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
                                "rejected_code": 503,
                                "rejected_msg" : "rejected",
                                "rules": [
                                    {
                                        "key": "${http_user}",
                                        "count": "${http_jack_count}",
                                        "time_window": 60,
                                        "header_prefix": "jack"
                                    },
                                    {
                                        "key": "${http_project}",
                                        "count": "${http_apisix_count}",
                                        "time_window": 60,
                                        "header_prefix": "bar"
                                    }
                                ]
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



=== TEST 13: match jack
--- request
GET /hello
--- more_headers
user: jack
jack-count: 2
--- error_code: 200
--- response_headers
X-Jack-RateLimit-Limit: 2
X-Jack-RateLimit-Remaining: 1
X-Jack-RateLimit-Reset: 60



=== TEST 14: match bar
--- request
GET /hello
--- more_headers
project: apisix
apisix-count: 3
--- error_code: 200
--- response_headers
X-Bar-RateLimit-Limit: 3
X-Bar-RateLimit-Remaining: 2
X-Bar-RateLimit-Reset: 60



=== TEST 15: setup route without header_prefix
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
                                "rejected_code": 503,
                                "rejected_msg" : "rejected",
                                "rules": [
                                    {
                                        "key": "${http_user}",
                                        "count": "${http_jack_count}",
                                        "time_window": 60
                                    },
                                    {
                                        "key": "${http_project}",
                                        "count": "${http_apisix_count}",
                                        "time_window": 60
                                    }
                                ]
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



=== TEST 16: match jack
--- request
GET /hello
--- more_headers
user: jack
jack-count: 2
--- error_code: 200
--- response_headers
X-1-RateLimit-Limit: 2
X-1-RateLimit-Remaining: 1
X-1-RateLimit-Reset: 60



=== TEST 17: match bar
--- request
GET /hello
--- more_headers
project: apisix
apisix-count: 3
--- error_code: 200
--- response_headers
X-2-RateLimit-Limit: 3
X-2-RateLimit-Remaining: 2
X-2-RateLimit-Reset: 60



=== TEST 18: use variable with default value in rules.key
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
                                "rejected_code": 503,
                                "rules": [
                                    {
                                        "count": 1,
                                        "time_window": 10,
                                        "key": "${http_project ?? apisix}"
                                    }
                                ]
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



=== TEST 19: with project header
--- request
GET /hello
--- more_headers
project: kubernetes
--- error_log eval
qr/limit key: \/apisix\/routes\/1:[^:]+:kubernetes/



=== TEST 20: without project header
--- request
GET /hello
--- error_log eval
qr/limit key: \/apisix\/routes\/1:[^:]+:apisix/
