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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
{"error_msg":"failed to check the configuration of plugin limit-count err: count/time_window and rules cannot be specified at the same time"}



=== TEST 2: configure multiple rules with same key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
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
qr/limit key: \/apisix\/routes\/limit-count-rules-1:[^:]+:kubernetes/



=== TEST 20: without project header
--- request
GET /hello
--- error_log eval
qr/limit key: \/apisix\/routes\/limit-count-rules-1:[^:]+:apisix/



=== TEST 21: setup route with rules using limit-count plugin directly
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/limit-count-rules-1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "rejected_code": 503,
                                "rules": [
                                    {
                                        "key": "${http_x_user}",
                                        "count": 2,
                                        "time_window": 60
                                    },
                                    {
                                        "key": "${http_x_project}",
                                        "count": 5,
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



=== TEST 22: match user rule via limit-count plugin directly
--- request
GET /hello
--- more_headers
x-user: testuser
x-project: myproject
--- error_code: 200



=== TEST 23: setup routes whose rule resolves its count per request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local conf = [[{
                "methods": ["GET"],
                "plugins": {
                    "limit-count": {
                        "rejected_code": 503,
                        "rules": [
                            {
                                "count": "${http_count ?? 3}",
                                "time_window": 60,
                                "key": "${http_x_user}"
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
                "uri": "%s"
            }]]
            for id, uri in pairs({["1"] = "/hello", ["2"] = "/hello1"}) do
                local code, body = t('/apisix/admin/routes/' .. id, ngx.HTTP_PUT,
                                     string.format(conf, uri))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 24: the same key limited under counts that change per request
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local function hit(uri, user, count)
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. uri, {
                    headers = {["X-User"] = user, ["Count"] = count},
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end
                ngx.say(uri, " ", user, " ", count or "-", ": ", res.status, " ",
                        res.headers["X-1-RateLimit-Limit"], " ",
                        res.headers["X-1-RateLimit-Remaining"])
            end
            hit("/hello", "u24", "3")
            hit("/hello", "u24", "5")
            hit("/hello", "u24", "3")
            hit("/hello", "u24", nil)
            hit("/hello", "u24", "5")
            hit("/hello", "u24", "5")
            hit("/hello", "other24", "3")
        }
    }
--- response_body
/hello u24 3: 200 3 2
/hello u24 5: 200 5 3
/hello u24 3: 200 3 0
/hello u24 -: 503 3 0
/hello u24 5: 200 5 0
/hello u24 5: 503 5 0
/hello other24 3: 200 3 2



=== TEST 25: a count that fails to resolve rejects only that request
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            for _, count in ipairs({"abc", "2", "-1", "2", "2"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. "/hello", {
                    headers = {["X-User"] = "u25", ["Count"] = count},
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end
                ngx.say(count, ": ", res.status, " ",
                        res.headers["X-1-RateLimit-Remaining"])
            end
        }
    }
--- response_body
abc: 500 nil
2: 200 1
-1: 500 nil
2: 200 0
2: 503 0
--- error_log
failed to get rate limit rules: resolved value is not a number
failed to get rate limit rules: resolved value must be a positive number



=== TEST 26: routes with the same rule shape keep separate counters
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            for _, uri in ipairs({"/hello", "/hello1", "/hello", "/hello1", "/hello"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. uri, {
                    headers = {["X-User"] = "u26", ["Count"] = "2"},
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end
                ngx.say(uri, ": ", res.status, " ", res.headers["X-1-RateLimit-Remaining"])
            end
        }
    }
--- response_body
/hello: 200 1
/hello1: 200 1
/hello: 200 0
/hello1: 200 0
/hello: 503 0



=== TEST 27: changing the plugin configuration starts a new counter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local function hit()
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. "/hello", {
                    headers = {["X-User"] = "u27", ["Count"] = "1"},
                })
                if not res then
                    return "failed: " .. err
                end
                return res.status
            end
            ngx.say(hit(), " ", hit())

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PATCH, [[{
                "plugins": {
                    "limit-count": {
                        "rejected_code": 429,
                        "rules": [
                            {
                                "count": "${http_count ?? 3}",
                                "time_window": 60,
                                "key": "${http_x_user}"
                            }
                        ]
                    }
                }
            }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)
            ngx.say(hit(), " ", hit())
        }
    }
--- response_body
200 503
200 429



=== TEST 28: rule header names follow a plugin metadata change
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "limit-count": {
                        "rejected_code": 503,
                        "rules": [
                            {
                                "count": 5,
                                "time_window": 60,
                                "key": "${http_x_user}",
                                "header_prefix": "jack"
                            }
                        ]
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local function hit()
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                    {headers = {["X-User"] = "u28"}})
                if not res then
                    ngx.say("failed: ", err)
                    return
                end
                ngx.say(res.headers["X-jack-RateLimit-Remaining"], " ",
                        res.headers["APISIX-jack-RateLimit-Remaining"])
            end
            hit()

            code, body = t('/apisix/admin/plugin_metadata/limit-count',
                ngx.HTTP_PUT, [[{
                    "limit_header": "APISIX-RateLimit-Limit",
                    "remaining_header": "APISIX-RateLimit-Remaining",
                    "reset_header": "APISIX-RateLimit-Reset"
                }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)
            hit()

            code, body = t('/apisix/admin/plugin_metadata/limit-count',
                ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)
            hit()
        }
    }
--- response_body
4 nil
nil 3
2 nil



=== TEST 29: a count resolved per request without rules is enforced per value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "limit-count": {
                        "count": "${http_count ?? 3}",
                        "time_window": 60,
                        "rejected_code": 503,
                        "key_type": "var",
                        "key": "http_x_user"
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local function hit(user, count)
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                    {headers = {["X-User"] = user, ["Count"] = count}})
                if not res then
                    ngx.say("failed: ", err)
                    return
                end
                ngx.say(user, " ", count or "-", ": ", res.status, " ",
                        res.headers["X-RateLimit-Limit"], " ",
                        res.headers["X-RateLimit-Remaining"])
            end
            hit("u29a", "1")
            hit("u29a", "1")
            hit("u29b", "2")
            hit("u29b", "2")
            hit("u29b", "2")
            hit("u29c")
        }
    }
--- response_body
u29a 1: 200 1 0
u29a 1: 503 1 0
u29b 2: 200 2 1
u29b 2: 200 2 0
u29b 2: 503 2 0
u29c -: 200 3 2
