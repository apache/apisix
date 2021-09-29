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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: invalid regular expression
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": [".+("]
                    }
                },
                "uri": "/hello"
            }]])

        if code >= 300 then
            ngx.status = code
        end
        ngx.print(body)
    }
}
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin uri-blocker err: pcre_compile() failed: missing ) in \".+(\""}
--- no_error_log
[error]



=== TEST 2: multiple valid rules
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["^a", "^b"]
                    }
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: multiple rules(include one invalid rule)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["^a", "^b("]
                    }
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin uri-blocker err: pcre_compile() failed: missing ) in \"^b(\""}
--- no_error_log
[error]



=== TEST 4: one block rule
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["aa"]
                    }
                },
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]],
            [[{
                "node": {
                    "value": {
                        "plugins": {
                            "uri-blocker": {
                                "block_rules": ["aa"]
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
--- no_error_log
[error]



=== TEST 5: hit block rule
--- request
GET /hello?aa=1
--- error_code: 403
--- no_error_log
[error]
--- error_log
concat block_rules: aa



=== TEST 6: miss block rule
--- request
GET /hello?bb=2
--- no_error_log
[error]
--- error_log
concat block_rules: aa



=== TEST 7: multiple block rules
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["aa", "bb", "c\\d+"]
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: hit block rule
--- request
GET /hello?x=bb
--- error_code: 403
--- no_error_log
[error]
--- error_log
concat block_rules: aa|bb|c\d+,



=== TEST 9: hit block rule
--- request
GET /hello?bb=2
--- error_code: 403
--- no_error_log
[error]
--- error_log
concat block_rules: aa|bb|c\d+,



=== TEST 10: hit block rule
--- request
GET /hello?c1=2
--- error_code: 403
--- no_error_log
[error]



=== TEST 11: not hit block rule
--- request
GET /hello?cc=2
--- no_error_log
[error]



=== TEST 12: SQL injection
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["select.+(from|limit)", "(?:(union(.*?)select))"]
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: hit block rule
--- request
GET /hello?name=;select%20from%20sys
--- error_code: 403
--- no_error_log
[error]
--- error_log
concat block_rules: select.+(from|limit)|(?:(union(.*?)select)),



=== TEST 14: hit block rule
--- request
GET /hello?name=;union%20select%20
--- error_code: 403
--- no_error_log
[error]



=== TEST 15: not hit block rule
--- request
GET /hello?cc=2
--- no_error_log
[error]



=== TEST 16: invalid rejected_msg length or type
--- config
location /t {
    content_by_lua_block {
        local data = {
            {
                input = {
                    plugins = {
                        ["uri-blocker"] = {
                            block_rules = { "^a" },
                            rejected_msg = "",
                        },
                    },
                    uri = "/hello",
                },
                output = {
                    error_msg = "failed to check the configuration of plugin uri-blocker err: property \"rejected_msg\" validation failed: string too short, expected at least 1, got 0",
                },
            },
            {
                input = {
                    plugins = {
                        ["uri-blocker"] = {
                            block_rules = { "^a" },
                            rejected_msg = true,
                        },
                    },
                    uri = "/hello",
                },
                output = {
                    error_msg = "failed to check the configuration of plugin uri-blocker err: property \"rejected_msg\" validation failed: wrong type: expected string, got boolean",
                },
            },
        }

        local t = require("lib.test_admin").test
        local err_count = 0
        for i in ipairs(data) do
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, data[i].input, data[i].output)

            if code >= 300 then
                err_count = err_count + 1
            end
            ngx.print(body)
        end

        assert(err_count == #data)
    }
}
--- request
GET /t
--- no_error_log
[error]



=== TEST 17: one block rule, with rejected_msg
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["aa"],
                        "rejected_msg": "access is not allowed"
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
--- request
GET /t
--- no_error_log
[error]



=== TEST 18: hit block rule and return rejected_msg
--- request
GET /hello?aa=1
--- error_code: 403
--- response_body
{"error_msg":"access is not allowed"}
--- no_error_log
[error]



=== TEST 19: one block rule, with case insensitive
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "uri-blocker": {
                        "block_rules": ["AA"],
                        "rejected_msg": "access is not allowed",
                        "case_insensitive": true
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
--- request
GET /t
--- no_error_log
[error]



=== TEST 20: hit block rule
--- request
GET /hello?aa=1
--- error_code: 403
--- response_body
{"error_msg":"access is not allowed"}
--- no_error_log
[error]
