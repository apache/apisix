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

=== TEST 1: add plugin with 'include_resp_body' setting
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- delete plugin metadata for response body format
            t('/apisix/admin/plugin_metadata/file-logger', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-body.log",
                                "include_resp_body": true
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



=== TEST 2: verify plugin for file-logger with response
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-resp-check.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code

            if new_msg.response ~= nil and new_msg.response.body == "hello world\n" then
                ngx.status = code
                ngx.say('contain with target')
            end
        }
    }
--- response_body
contain with target



=== TEST 3: check file-logger 'include_resp_body' with 'expr'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-expr-body.log",
                                "include_resp_body": true,
                                "include_resp_body_expr": [
                                    [
                                      "arg_foo",
                                      "==",
                                      "bar"
                                    ]
                                ]
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



=== TEST 4: verify file-logger resp with expression of concern
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?foo=bar", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-expr-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-resp-expr-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code

            if new_msg.response ~= nil and new_msg.response.body == "hello world\n" then
                ngx.status = code
                ngx.say('contain target body hits with expr')
            end

            --- a new request is logged
            t("/hello?name=pix", ngx.HTTP_GET)
            msg = fd:read("*l")
            local new_msg = core.json.decode(msg)
            if new_msg.response.body == nil then
                ngx.say('skip unconcern body')
            end
        }
    }
--- response_body
contain target body hits with expr
skip unconcern body



=== TEST 5: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr",
                        "resp_body": "$resp_body"
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



=== TEST 6: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-body2.log",
                                "include_resp_body": true
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
--- response_body
passed



=== TEST 7: verify plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-body2.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.resp_body == 'hello world\n'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end
        }
    }
--- response_body
write file log success



=== TEST 8: Add new configuration with match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-match.log",
                                "match": [
                                    [
                                        [ "arg_name","==","jack" ]
                                    ]
                                ],
                                "log_format": {
                                    "request": "$request"
                                }
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
--- response_body
passed



=== TEST 9: Request match
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?name=jack", ngx.HTTP_GET)
            local fd, err = io.open("file-with-match.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-with-match.log, error info: ", err)
                return
            end
            local msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.request == 'GET /hello?name=jack HTTP/1.1'
                and new_msg.route_id == '1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end

            os.remove("file-with-match.log")
        }
    }
--- response_body
write file log success



=== TEST 10: Request not match
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?name=tony", ngx.HTTP_GET)
            local fd, err = io.open("file-with-match.log", 'r')
            if not fd then
                local msg = "not write file log"
                ngx.say(msg)
                return
            end
        }
    }
--- response_body
not write file log



=== TEST 11: add plugin with 'include_req_body' setting
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/file-logger', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-req-body.log",
                                "include_req_body": true
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



=== TEST 12: verify plugin for file-logger with request
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_POST, "body-data")
            local fd, err = io.open("file-with-req-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-req-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code
            if new_msg.request ~= nil and new_msg.request.body == "body-data" then
                ngx.status = code
                ngx.say('contain with target')
            end
        }
    }
--- response_body
contain with target



=== TEST 13: check file-logger 'include_req_body' with 'expr'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-req-expr-body.log",
                                "include_req_body": true,
                                "include_req_body_expr": [
                                    [
                                      "arg_log_body",
                                      "==",
                                      "yes"
                                    ]
                                ]
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



=== TEST 14: verify file-logger req with expression of concern
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?log_body=yes",
                ngx.HTTP_POST,
                [[{"foo": "bar"}]]
                )
            local fd, err = io.open("file-with-req-expr-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-req-expr-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code
            if new_msg.request ~= nil and new_msg.request.body ~= nil then
                ngx.status = code
                ngx.say('contain target body hits with expr')
            end

            --- a new request is logged
            t("/hello?log_body=no", ngx.HTTP_POST, [[{"foo": "b"}]])
            msg = fd:read("*l")
            local new_msg = core.json.decode(msg)
            if new_msg.request.body == nil then
                ngx.say('skip unconcern body')
            end
        }
    }
--- response_body
contain target body hits with expr
skip unconcern body
