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
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.consumer-restriction")
            local conf = {
                whitelist = {
                    "jack1",
                    "jack2"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"whitelist":["jack1","jack2"]}
--- no_error_log
[error]



=== TEST 2: whitelist and blacklist mutual exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.consumer-restriction")
            local ok, err = plugin.check_schema({whitelist={"jack1"}, blacklist={"jack2"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
value should match only one schema, but matches both schemas 1 and 2
done
--- no_error_log
[error]



=== TEST 3: add consumer jack1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2019",
                            "password": "123456"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack1",
                            "plugins": {
                                "basic-auth": {
                                    "username": "jack2019",
                                    "password": "123456"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: add consumer jack2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack2",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2020",
                            "password": "123456"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack2",
                            "plugins": {
                                "basic-auth": {
                                    "username": "jack2020",
                                    "password": "123456"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "whitelist": [
                                     "jack1"
                                 ]
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



=== TEST 6: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 7: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 8: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer is not allowed"}
--- no_error_log
[error]



=== TEST 9: set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "blacklist": [
                                     "jack1"
                                 ]
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




=== TEST 10: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 11: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer is not allowed"}
--- no_error_log
[error]



=== TEST 12: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 13: set whitelist without authorization
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "consumer-restriction": {
                                 "whitelist": [
                                     "jack1"
                                 ]
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



=== TEST 14: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 15: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 16: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 17: set blacklist without authorization
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "consumer-restriction": {
                                 "blacklist": [
                                     "jack1"
                                 ]
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



=== TEST 18: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 19: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 20: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 21: remove consumer-restriction
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
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



=== TEST 22: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 23: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 24: verify unauthorized
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
