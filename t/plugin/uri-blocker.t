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

repeat_each(2);
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
--- error_log
concat block_rules: ^a|^b,



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



=== TEST 4: sanity
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
--- error_log
concat block_rules: aa,



=== TEST 5: hit block rule
--- request
GET /hello?aa=1
--- error_code: 403
--- no_error_log
[error]



=== TEST 6: miss block rule
--- request
GET /hello?bb=2
--- no_error_log
[error]



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
--- error_log
concat block_rules: aa|bb|c\d+,



=== TEST 8: hit block rule
--- request
GET /hello?x=bb
--- error_code: 403
--- no_error_log
[error]



=== TEST 9: hit block rule
--- request
GET /hello?bb=2
--- error_code: 403
--- no_error_log
[error]



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
--- error_log
concat block_rules: select.+(from|limit)|(?:(union(.*?)select)),



=== TEST 13: hit block rule
--- request
GET /hello?name=;select%20from%20sys
--- error_code: 403
--- no_error_log
[error]



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
