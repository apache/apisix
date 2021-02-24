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

=== TEST 1: set global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/global_rules/1',
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
                        },
                        "key": "/apisix/global_rules/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/global_rules/1'))
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
--- no_error_log
[error]



=== TEST 2: get global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_GET,
                nil,
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
                        },
                        "key": "/apisix/global_rules/1"
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



=== TEST 3: list global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "dir": true,
                        "nodes": [
                        {
                            "key": "/apisix/global_rules/1",
                            "value": {
                            "plugins": {
                                "limit-count": {
                                "time_window": 60,
                                "policy": "local",
                                "count": 2,
                                "key": "remote_addr",
                                "rejected_code": 503
                                }
                            }
                            }
                        }
                        ],
                        "key": "/apisix/global_rules"
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



=== TEST 4: PATCH global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/global_rules/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PATCH,
                [[{
                    "plugins": {
                    "limit-count": {
                        "count": 3,
                        "time_window": 60,
                        "rejected_code": 503,
                        "key": "remote_addr"
                    }
                }}]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 3,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/global_rules/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/global_rules/1'))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: PATCH global rules (sub path)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/global_rules/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/global_rules/1/plugins',
                ngx.HTTP_PATCH,
                [[{
                    "limit-count": {
                        "count": 3,
                        "time_window": 60,
                        "rejected_code": 503,
                        "key": "remote_addr"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 3,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/global_rules/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/global_rules/1'))
            local create_time = res.body.node.value.create_time
            assert(prev_create_time == create_time, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
            assert(prev_update_time ~= update_time, "update_time should be changed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: delete global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/global_rules/1',
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



=== TEST 7: delete global rules(not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/global_rules/1',
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



=== TEST 8: set global rules(invalid host option)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "host": "foo.com",
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

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: additional properties forbidden, found host"}
--- no_error_log
[error]



=== TEST 9: set global rules(missing plugins)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{}]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"plugins\" is required"}
--- no_error_log
[error]



=== TEST 10: string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/a-b-c-ABC_0123',
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



=== TEST 11: string id(DELETE)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/a-b-c-ABC_0123',
                ngx.HTTP_DELETE
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



=== TEST 12: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.node.value.create_time = nil
            res.node.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"set","node":{"key":"/apisix/global_rules/1","value":{"id":"1","plugins":{"proxy-rewrite":{"uri":"/"}}}}}
--- request
GET /t
--- no_error_log
[error]



=== TEST 13: not unwanted data, PATCH
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PATCH,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.node.value.create_time = nil
            res.node.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"compareAndSwap","node":{"key":"/apisix/global_rules/1","value":{"id":"1","plugins":{"proxy-rewrite":{"uri":"/"}}}}}
--- request
GET /t
--- no_error_log
[error]



=== TEST 14: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_GET
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            local value = res.node.value
            assert(value.create_time ~= nil)
            value.create_time = nil
            assert(value.update_time ~= nil)
            value.update_time = nil
            assert(res.count ~= nil)
            res.count = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"get","node":{"key":"/apisix/global_rules/1","value":{"id":"1","plugins":{"proxy-rewrite":{"uri":"/"}}}}}
--- request
GET /t
--- no_error_log
[error]



=== TEST 15: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"delete","deleted":"1","key":"/apisix/global_rules/1","node":{}}
--- request
GET /t
--- no_error_log
[error]
