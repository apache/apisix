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

=== TEST 1: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/services/1',
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
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new service"
                    },
                    "key": "/apisix/services/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/services/1'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: get service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 3: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message,res = t('/apisix/admin/services/1', ngx.HTTP_DELETE)

            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 4: delete service(id: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/services/not_found', ngx.HTTP_DELETE)

            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404



=== TEST 5: post service + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
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
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        }
                    }
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.key, #"/apisix/services/" + 1)
            local res = assert(etcd.get('/services/' .. id))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

            code, message = t('/apisix/admin/services/' .. id, ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed



=== TEST 6: uri + upstream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1',
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
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        }
                    }
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



=== TEST 7: uri + plugins
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1',
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



=== TEST 8: invalid service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/invalid_id$',
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



=== TEST 9: invalid id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "id": 3,
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



=== TEST 10: id in the rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_PUT,
                [[{
                    "id": "1",
                    "plugins": {}
                }]],
                [[{
                    "value": {
                        "plugins": {}
                    },
                    "key": "/apisix/services/1"
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



=== TEST 11: integer id less than 1
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
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the required"}



=== TEST 12: invalid service id: string value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_PUT,
                [[{
                    "id": "invalid_id$",
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
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the required"}



=== TEST 13: invalid upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_PUT,
                [[{
                    "id": 1,
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
{"error_msg":"invalid configuration: property \"upstream_id\" validation failed: object matches none of the required"}



=== TEST 14: not exist upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_PUT,
                [[{
                    "id": 1,
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



=== TEST 15: wrong service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 16: wrong service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services',
                ngx.HTTP_POST,
                [[{
                    "id": 1,
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



=== TEST 17: patch service(whole)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")

            local id = 1
            local res = assert(etcd.get('/services/' .. id))
            local prev_create_time = res.body.node.value.create_time
            local prev_update_time = res.body.node.value.update_time
            ngx.sleep(1)

            local code, body = t('/apisix/admin/services/1',
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
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new 20 service"
                    },
                    "key": "/apisix/services/1"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/services/' .. id))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 18: patch service(new desc)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PATCH,
                [[{
                    "desc": "new 19 service"
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new 19 service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 19: patch service(new nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 20: patch service(whole - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1/',
                ngx.HTTP_PATCH,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new 22 service"
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new 22 service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 21: patch service(new desc - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1/desc',
                ngx.HTTP_PATCH,
                '"new 23 service"',
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new 23 service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 22: patch service(new nodes - sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1/upstream',
                ngx.HTTP_PATCH,
                [[{
                    "nodes": {
                        "127.0.0.2:8081": 3,
                        "127.0.0.3:8082": 4
                    },
                    "type": "roundrobin"
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.2:8081": 3,
                                "127.0.0.3:8082": 4
                            },
                            "type": "roundrobin"
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



=== TEST 23: set service(id: 1) and upstream(type:chash, default hash_on: vars, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 24: set service(id: 1) and upstream(type:chash, hash_on: header, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 25: set service(id: 1) and upstream(type:chash, hash_on: cookie, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 26: set service(id: 1) and upstream(type:chash, hash_on: consumer, missing key is ok)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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



=== TEST 27: set service(id: 1 + test service name)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "name": "test service name"
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "test service name"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 28: invalid string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/*invalid',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
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
--- error_code: 400



=== TEST 29: set empty service. (id: 1)（allow empty `service` object）
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                '{}',
                [[{
                    "value": {
                        "id":"1"
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



=== TEST 30: patch content to the empty service.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PATCH,
                [[{
                    "desc": "empty service",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:80": 1
                        }
                    }
                }]],
                [[{
                    "value":{
                        "desc":"empty service",
                        "plugins":{
                            "limit-count":{
                                "time_window":60,
                                "count":2,
                                "rejected_code":503,
                                "key":"remote_addr",
                                "policy":"local"
                            }
                        },
                        "upstream":{
                            "type":"roundrobin",
                            "nodes":{
                                "127.0.0.1:80":1
                            },
                            "hash_on":"vars",
                            "pass_host":"pass"
                        },
                        "id":"1"
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



=== TEST 31: set service(with labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "labels": {
                        "build":"16",
                        "env":"production",
                        "version":"v2"
                    },
                    "desc": "new service"
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "labels": {
                            "build": "16",
                            "env": "production",
                            "version": "v2"
                        },
                        "desc": "new service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 32: patch service(change labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PATCH,
                [[{
                    "labels": {
                        "build": "17"
                    }
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "labels": {
                            "build": "17",
                            "env": "production",
                            "version": "v2"
                        },
                        "desc": "new service"
                    },
                    "key": "/apisix/services/1"
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



=== TEST 33: invalid format of label value: set service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "labels": {
                        "env": ["production", "release"]
                    },
                    "desc": "new service"
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
{"error_msg":"invalid configuration: property \"labels\" validation failed: failed to validate env (matching \".*\"): wrong type: expected string, got table"}



=== TEST 34: create service with create_time and update_time(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "create_time": 1602883670,
                        "update_time": 1602893670
                    }
                }]],
                [[{
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin",
                            "create_time": 1602883670,
                            "update_time": 1602893670
                        }
                    },
                    "key": "/apisix/services/1"
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



=== TEST 35: delete test service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 36: limit the length of service's name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1', ngx.HTTP_PUT,
                require("toolkit.json").encode({name = ("1"):rep(101)}))

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"name\" validation failed: string too long, expected at most 100, got 101"}



=== TEST 37: allow dot in the id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/a.b',
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
                    "value": {
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new service"
                    },
                    "key": "/apisix/services/a.b"
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
