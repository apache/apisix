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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.echo")
            local ok, err = plugin.check_schema({before_body = "body before", body = "body to attach",
            after_body = "body to attach"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: wrong type of integer
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.echo")
            local ok, err = plugin.check_schema({before_body = "body before", body = "body to attach",
            after_body = 10})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "after_body" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "echo": {
                                "before_body": "before the body modification ",
                                "body":"hello upstream",
                                "after_body": " after the body modification.",
                                "headers": {
                                    "Location":"https://www.iresty.com",
                                    "Authorization": "userpass"
                                }
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
                               "echo": {
                                "before_body": "before the body modification ",
                                "body":"hello upstream",
                                "headers": {
                                    "Location":"https://www.iresty.com"
                                 },
                               }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 4: access
--- request
GET /hello
--- response_body chomp
before the body modification hello upstream after the body modification.
--- response_headers
Location: https://www.iresty.com
Authorization: userpass
--- no_error_log
[error]
--- wait: 0.2



=== TEST 5: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "echo": {
                                "before_body": "before the body modification ",
                                "headers": {
                                    "Location":"https://www.iresty.com"
                                }
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
                               "echo": {
                                "before_body": "before the body modification ",
                                "headers": {
                                    "Location":"https://www.iresty.com"
                                }
                               }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 6: access without upstream body change
--- request
GET /hello
--- response_body
before the body modification hello world
--- response_headers
Location: https://www.iresty.com
--- wait: 0.2
--- no_error_log
[error]
--- wait: 0.2



=== TEST 7: print the `conf` in etcd, no dirty data
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local encode_with_keys_sorted = require("toolkit.json").encode

            local code, _, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "echo": {
                            "before_body": "before the body modification ",
                            "headers": {
                                "Location":"https://www.iresty.com"
                            }
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            local resp_data = core.json.decode(body)
            ngx.say(encode_with_keys_sorted(resp_data.node.value.plugins))
        }
    }
--- request
GET /t
--- response_body
{"echo":{"before_body":"before the body modification ","headers":{"Location":"https://www.iresty.com"}}}
--- no_error_log
[error]



=== TEST 8: set body with chunked upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "echo": {
                                "body":"hello upstream"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello_chunked"
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



=== TEST 9: access
--- request
GET /hello_chunked
--- response_body chomp
hello upstream
--- no_error_log
[error]



=== TEST 10: add before/after body with chunked upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "echo": {
                                "before_body": "before the body modification ",
                                "after_body": " after the body modification."
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello_chunked"
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



=== TEST 11: access
--- request
GET /hello_chunked
--- response_body chomp
before the body modification hello world
 after the body modification.
--- no_error_log
[error]
