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
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (! $block->request) {
        $block->set_value("request", "GET /t");
        if (!$block->response_body) {
            $block->set_value("response_body", "passed\n");
        }
    }
});


run_tests;

__DATA__

=== TEST 1: mask query
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "remove",
                                        "name": "password",
                                        "type": "query"
                                    },
                                    {
                                        "action": "replace",
                                        "name": "token",
                                        "type": "query",
                                        "value": "*****"
                                    },
                                    {
                                        "action": "regex",
                                        "name": "card",
                                        "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
                                        "type": "query",
                                        "value": "$1-****-****-$2"
                                    }
                                ]
                            },
                            "file-logger": {
                                "path": "mask-query.log.1"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 2: verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code = t("/hello?password=abc&token=xyz&card=1234-1234-1234-1234", ngx.HTTP_GET)
            local fd, err = io.open("mask-query.log.1", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)

            if log.request.querystring.password then
                ngx.say("password arg mask failed: " .. log.request.querystring.password)
                return
            end
            if log.request.querystring.token ~= "*****" then
                ngx.say("token arg mask failed: " .. log.request.querystring.token)
                return
            end
            if log.request.querystring.card ~= "1234-****-****-1234" then
                ngx.say("card arg mask failed: " .. log.request.querystring.card)
                return
            end
            if log.request.uri ~= "/hello?token=*****&card=1234-****-****-1234" and
               log.request.uri ~= "/hello?card=1234-****-****-1234&token=*****" then
                ngx.say("uri mask failed: " .. log.request.uri)
                return
            end

            os.remove("mask-query.log.1")
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 3: mask header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "remove",
                                        "name": "password",
                                        "type": "header"
                                    },
                                    {
                                        "action": "replace",
                                        "name": "token",
                                        "type": "header",
                                        "value": "*****"
                                    },
                                    {
                                        "action": "regex",
                                        "name": "card",
                                        "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
                                        "type": "header",
                                        "value": "$1-****-****-$2"
                                    }
                                ]
                            },
                            "file-logger": {
                                "path": "mask-header.log.2"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 4: verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local headers = {}
            headers["password"] = "abc"
            headers["token"] = "xyz"
            headers["card"] = "1234-1234-1234-1234"
            local code = t("/hello", ngx.HTTP_GET, "", nil, headers)

            local fd, err = io.open("mask-header.log.2", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)

            if log.request.headers.password then
                ngx.say("password header mask failed: " .. log.request.headers.password)
                return
            end
            if log.request.headers.token ~= "*****" then
                ngx.say("token header mask failed: " .. log.request.headers.token)
                return
            end
            if log.request.headers.card ~= "1234-****-****-1234" then
                ngx.say("card header mask failed: " .. log.request.headers.card)
                return
            end

            os.remove("mask-header.log.2")
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 5: mask urlencoded body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "remove",
                                        "body_format": "urlencoded",
                                        "name": "password",
                                        "type": "body"
                                    },
                                    {
                                        "action": "replace",
                                        "body_format": "urlencoded",
                                        "name": "token",
                                        "type": "body",
                                        "value": "*****"
                                    },
                                    {
                                        "action": "regex",
                                        "body_format": "urlencoded",
                                        "name": "card",
                                        "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
                                        "type": "body",
                                        "value": "$1-****-****-$2"
                                    }
                                ]
                            },
                            "file-logger": {
                                "include_req_body": true,
                                "path": "mask-urlencoded-body.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 6: verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code = t("/hello", ngx.HTTP_POST, "password=abc&token=xyz&card=1234-1234-1234-1234")

            local fd, err = io.open("mask-urlencoded-body.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)

            if log.request.body ~= "token=*****&card=1234-****-****-1234" and
               log.request.body ~= "card=1234-****-****-1234&token=*****" then
                ngx.say("urlencoded body mask failed: " .. log.request.body)
                return
            end

            os.remove("mask-urlencoded-body.log")
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 7: mask json body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "remove",
                                        "body_format": "json",
                                        "name": "$.password",
                                        "type": "body"
                                    },
                                    {
                                        "action": "replace",
                                        "body_format": "json",
                                        "name": "users[*].token",
                                        "type": "body",
                                        "value": "*****"
                                    },
                                    {
                                        "action": "regex",
                                        "body_format": "json",
                                        "name": "$.users[*].credit.card",
                                        "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
                                        "type": "body",
                                        "value": "$1-****-****-$2"
                                    }
                                ]
                            },
                            "file-logger": {
                                "include_req_body": true,
                                "path": "mask-json-body.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 8: verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code = t("/hello",
                ngx.HTTP_POST,
                [[{
                  "password": "abc",
                  "users": [
                    {
                      "token": "xyz",
                      "credit": {
                        "card": "1234-1234-1234-1234"
                      }
                    },
                    {
                      "token": "xyz",
                      "credit": {
                        "card": "1234-1234-1234-1234"
                      }
                    }
                  ]
                }]]
            )

            local fd, err = io.open("mask-json-body.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)

            local body = core.json.decode(log.request.body)
            if body.password then
                ngx.say("$.password mask failed: " .. body.password)
                return
            end
            for _, user in ipairs(body.users) do
                if user.token ~= "*****" then
                    ngx.say("$.users[*].token mask failed: " .. user.token)
                    return
                end
                if user.credit.card ~= "1234-****-****-1234" then
                    ngx.say("$.users[*].credit.card mask failed: " .. user.credit.card)
                    return
                end
            end

            os.remove("mask-json-body.log")
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 9: plugin within global rule should not throw error for missing body.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "remove",
                                        "name": "password",
                                        "type": "query"
                                    },
                                    {
                                        "action": "replace",
                                        "name": "token",
                                        "type": "query",
                                        "value": "*****"
                                    },
                                    {
                                        "action": "regex",
                                        "name": "card",
                                        "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
                                        "type": "query",
                                        "value": "$1-****-****-$2"
                                    }
                                ]
                            },
                            "file-logger": {
                                "path": "mask-query.log.4"
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



=== TEST 10: verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code = t("/random", ngx.HTTP_POST, "password=abc&token=xyz&card=1234-1234-1234-1234")

            ngx.say("code: ", code)
        }
    }
--- response_body
code: 404
--- no_error_log
no request body found



=== TEST 11: create plugin with default value for `max_req_post_args`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "regex",
                                        "body_format": "urlencoded",
                                        "name": "arg100",
                                        "regex": "(\\d+)$",
                                        "type": "body",
                                        "value": "$1"
                                    }
                                ]
                            },
                            "file-logger": {
                                "include_req_body": true,
                                "path": "mask-urlencoded-body.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 12: verify default value for `max_req_post_args``
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local url_encoded = "arg1=1"
            for i = 2, 110, 1 do
                url_encoded = url_encoded .. "&arg" .. i .. "=" .. i
            end

            local code = t("/hello", ngx.HTTP_POST, url_encoded)

            local fd, err = io.open("mask-urlencoded-body.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)
            local match100, err = ngx.re.match(log.request.body, "arg100=100")
            local match101, err = ngx.re.match(log.request.body, "arg101=101")
            os.remove("mask-urlencoded-body.log")
            if match100 and not match101 then
                ngx.say("success")
                return
            end
            ngx.say(match)
            ngx.say(err)
        }
    }
--- response_body
success



=== TEST 13: create plugin with custom `max_req_post_args` value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "data-mask": {
                                "request": [
                                    {
                                        "action": "regex",
                                        "body_format": "urlencoded",
                                        "name": "arg10",
                                        "regex": "(\\d+)$",
                                        "type": "body",
                                        "value": "$1"
                                    }
                                ],
                                "max_req_post_args": 10
                            },
                            "file-logger": {
                                "include_req_body": true,
                                "path": "mask-urlencoded-body.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 14: verify number of args
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local url_encoded = "arg1=1"
            for i = 2, 110, 1 do
                url_encoded = url_encoded .. "&arg" .. i .. "=" .. i
            end

            local code = t("/hello", ngx.HTTP_POST, url_encoded)

            local fd, err = io.open("mask-urlencoded-body.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            local log = core.json.decode(line)
            local match10, err = ngx.re.match(log.request.body, "arg10=10")
            local match11, err = ngx.re.match(log.request.body, "arg11=11")
            os.remove("mask-urlencoded-body.log")
            if match10 and not match11 then
                ngx.say("success")
                return
            end
            ngx.say(match)
            ngx.say(err)

        }
    }
--- response_body
success
