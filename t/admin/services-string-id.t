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
log_level("info");

run_tests;

__DATA__

=== TEST 1: set service(id: 5eeb3dc90f747328b2930b0b)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new service"
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new service"
                        },
                        "key": "/apisix/services/5eeb3dc90f747328b2930b0b"
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



=== TEST 2: get service(id: 5eeb3dc90f747328b2930b0b)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new service"
                        },
                        "key": "/apisix/services/5eeb3dc90f747328b2930b0b"
                    },
                    "action": "get"
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



=== TEST 3: delete service(id: 5eeb3dc90f747328b2930b0b)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: delete service(id: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/services/not_found',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )

            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404
--- no_error_log
[error]



=== TEST 5: post service + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services',
                 ngx.HTTP_POST,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        }
                    },
                    "action": "create"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/services/" + 1)
            code, message = t('/apisix/admin/services/' .. id,
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 6: uri + upstream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
--- no_error_log
[error]



=== TEST 7: uri + plugins
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
--- no_error_log
[error]



=== TEST 8: invalid empty plugins (todo)
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {}
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- error_code: 400
--- SKIP



=== TEST 9: invalid service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/*invalid_id$',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.exit(code)
        }
    }
--- request
GET /t
--- error_code: 400
--- no_error_log
[error]



=== TEST 10: invalid id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "3",
                    "plugins": {}
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong service id"}
--- no_error_log
[error]



=== TEST 11: id in the rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "5eeb3dc90f747328b2930b0b",
                    "plugins": {}
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {}
                        },
                        "key": "/apisix/services/5eeb3dc90f747328b2930b0b"
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



=== TEST 12: integer id less than 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": -100,
                    "plugins": {}
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 13: invalid service id: contains symbols value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "*invalid_id$",
                    "plugins": {}
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 14: no additional properties is valid
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "5eeb3dc90f747328b2930b0b",
                    "invalid_property": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: additional properties forbidden, found invalid_property"}
--- no_error_log
[error]



=== TEST 15: invalid upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "5eeb3dc90f747328b2930b0b",
                    "upstream_id": "invalid$"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream_id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 16: not exist upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "5eeb3dc90f747328b2930b0b",
                    "upstream_id": "9999999999"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to fetch upstream info by upstream id [9999999999], response code: 404"}
--- no_error_log
[error]



=== TEST 17: wrong service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_POST,
                 [[{
                    "plugins": {}
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong service id, do not need it"}
--- no_error_log
[error]



=== TEST 18: wrong service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_POST,
                [[{
                    "id": "5eeb3dc90f747328b2930b0b",
                    "plugins": {}
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong service id, do not need it"}
--- no_error_log
[error]



=== TEST 19: patch service(whole)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                ngx.HTTP_PATCH,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new 20 service"
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new 20 service"
                        },
                        "key": "/apisix/services/5eeb3dc90f747328b2930b0b"
                    },
                    "action": "compareAndSwap"
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



=== TEST 20: patch service(new desc)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                ngx.HTTP_PATCH,
                [[{
                    "desc": "new 19 service"
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new 19 service"
                        },
                        "key": "/apisix/services/5eeb3dc90f747328b2930b0b"
                    },
                    "action": "compareAndSwap"
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



=== TEST 21: patch service(new nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                ngx.HTTP_PATCH,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8081": 3,
                            "127.0.0.1:8082": 4
                        },
                        "type": "roundrobin"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1,
                                    "127.0.0.1:8081": 3,
                                    "127.0.0.1:8082": 4
                                },
                                "type": "roundrobin"
                            }
                        }
                    }
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



=== TEST 22: set service(id: 5eeb3dc90f747328b2930b0b) and upstream(type:chash, default hash_on: vars, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash"
                    },
                    "desc": "new service"
                }]])

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 23: set service(id: 5eeb3dc90f747328b2930b0b) and upstream(type:chash, hash_on: header, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on": "header"
                    },
                    "desc": "new service"
                }]])

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 24: set service(id: 5eeb3dc90f747328b2930b0b) and upstream(type:chash, hash_on: cookie, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on": "cookie"
                    },
                    "desc": "new service"
                }]])

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 25: set service(id: 5eeb3dc90f747328b2930b0b) and upstream(type:chash, hash_on: consumer, missing key is ok)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/5eeb3dc90f747328b2930b0b',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on": "consumer"
                    },
                    "desc": "new service"
                }]])

            ngx.status = code
            ngx.say(code .. " " .. body)
        }
    }
--- request
GET /t
--- response_body
200 passed
--- no_error_log
[error]
