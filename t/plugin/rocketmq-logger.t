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
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 rocketmq_topic = "test",
                 key = "key1",
                 nameserver_list = {
                    ["127.0.0.1"] = 3
                 }
            })
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



=== TEST 2: missing nameserver list
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({rocketmq_topic = "test", key= "key1"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "nameserver_list" is required
done
--- no_error_log
[error]



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                nameserver_list = {
                    ["127.0.0.1"] = 3000
                },
                timeout = "10",
                rocketmq_topic ="test",
                key= "key1"
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
done
--- no_error_log
[error]



=== TEST 4: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" :
                                  {
                                    "127.0.0.1":9876
                                  },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1
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
                                 "rocketmq-logger": {
                                    "nameserver_list" :
                                      {
                                        "127.0.0.1":9876
                                      },
                                    "rocketmq_topic" : "test2",
                                    "key" : "key1",
                                    "timeout" : 1,
                                    "batch_max_size": 1
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



=== TEST 5: access
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
--- wait: 2



=== TEST 6: error log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                             "rocketmq-logger": {
                                    "nameserver_list" :
                                      {
                                        "127.0.0.1":9876,
                                        "127.0.0.1":9877
                                      },
                                    "rocketmq_topic" : "test2",
                                    "producer_type": "sync",
                                    "key" : "key1",
                                    "batch_max_size": 1
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
                                "rocketmq-logger": {
                                    "nameserver_list" :
                                      {
                                        "127.0.0.1":9876,
                                        "127.0.0.1":9877
                                      },
                                    "rocketmq_topic" : "test2",
                                    "producer_type": "sync",
                                    "key" : "key1",
                                    "batch_max_size": 1
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
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
        }
    }
--- request
GET /t
--- error_log
failed to send data to rocketmq topic
[error]
--- wait: 1



=== TEST 7: set route(meta_format = origin, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1":9876
                                },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": true,
                                "meta_format": "origin"
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



=== TEST 8: hit route, report log to rocketmq
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log
send data to rocketmq: GET /hello?ab=cd HTTP/1.1
host: localhost
content-length: 6
connection: close

abcdef
--- wait: 2



=== TEST 9: set route(meta_format = origin, include_req_body = false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1":9876
                                },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false,
                                "meta_format": "origin"
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



=== TEST 10: hit route, report log to rocketmq
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log
send data to rocketmq: GET /hello?ab=cd HTTP/1.1
host: localhost
content-length: 6
connection: close
--- wait: 2



=== TEST 11: set route(meta_format = default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1":9876
                                },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false
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



=== TEST 12: hit route, report log to rocketmq
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log_like eval
qr/send data to rocketmq: \{.*"upstream":"127.0.0.1:1980"/
--- wait: 2



=== TEST 13: set route(id: 1), missing key field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" :
                                  {
                                    "127.0.0.1":9876
                                  },
                                "rocketmq_topic" : "test2",
                                "timeout" : 1,
                                "batch_max_size": 1
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
                                 "rocketmq-logger": {
                                    "nameserver_list" :
                                      {
                                        "127.0.0.1":9876
                                      },
                                    "rocketmq_topic" : "test2",
                                    "timeout" : 1,
                                    "batch_max_size": 1
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



=== TEST 14: access, test key field is optional
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
--- wait: 2



=== TEST 15: set route(meta_format = default), missing key field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1":9876
                                },
                                "rocketmq_topic" : "test2",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false
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



=== TEST 16: hit route, report log to rocketmq
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log_like eval
qr/send data to rocketmq: \{.*"upstream":"127.0.0.1:1980"/
--- wait: 2



=== TEST 17: use the topic with 3 partitions
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1": 9876
                                },
                                "rocketmq_topic" : "test3",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false
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



=== TEST 18: report log to rocketmq by different partitions
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1": 9876
                                },
                                "rocketmq_topic" : "test3",
                                "producer_type": "sync",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false
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

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
        }
    }
--- request
GET /t
--- timeout: 5s
--- ignore_response
--- no_error_log
[error]
--- error_log eval
[qr/queue: 1/,
qr/queue: 0/,
qr/queue: 2/]



=== TEST 19: report log to rocketmq by different partitions in async mode
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : {
                                    "127.0.0.1": 9876
                                },
                                "rocketmq_topic" : "test3",
                                "producer_type": "async",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "include_req_body": false
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
            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)
        }
    }
--- request
GET /t
--- timeout: 5s
--- ignore_response
--- no_error_log
[error]
--- error_log eval
[qr/queue: 1/,
qr/queue: 0/,
qr/queue: 2/]



=== TEST 20: update the nameserver_list, generate different rocketmq producers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )
            ngx.sleep(0.5)

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" : {
                                "127.0.0.1": 9876
                            },
                            "rocketmq_topic" : "test2",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" : {
                                "127.0.0.1": 19876
                            },
                            "rocketmq_topic" : "test4",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response
passed
--- wait: 5
--- error_log
phase_func(): rocketmq nameserver_list[1] port 9876
phase_func(): rocketmq nameserver_list[1] port 19876
--- no_error_log eval
qr/not found topic/



=== TEST 21: use the topic that does not exist on rocketmq(even if rocketmq allows auto create topics, first time push messages to rocketmq would got this error)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" : {
                                "127.0.0.1": 9876
                            },
                            "rocketmq_topic" : "undefined_topic",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 5
--- response
passed
--- error_log eval
qr/getTopicRouteInfoFromNameserver return TOPIC_NOT_EXIST, No topic route info in name server for the topic: undefined_topic/



=== TEST 22: check nameserver_list via schema
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    input = {
                        nameserver_list = {},
                        rocketmq_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        nameserver_list = {
                            ["127.0.0.1"] = "9876"
                        },
                        rocketmq_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        nameserver_list = {
                            ["127.0.0.1"] = 0
                        },
                        rocketmq_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        nameserver_list = {
                            ["127.0.0.1"] = 65536
                        },
                        rocketmq_topic = "test",
                        key= "key1",
                    },
                },
            }

            local plugin = require("apisix.plugins.rocketmq-logger")

            local err_count = 0
            for i in ipairs(data) do
                local ok, err = plugin.check_schema(data[i].input)
                if not ok then
                    err_count = err_count + 1
                    ngx.say(err)
                end
            end

            assert(err_count == #data)
        }
    }
--- request
GET /t
--- response_body
property "nameserver_list" validation failed: expect object to have at least 1 properties
property "nameserver_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): wrong type: expected integer, got string
property "nameserver_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): expected 0 to be greater than 1
property "nameserver_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): expected 65536 to be smaller than 65535
--- no_error_log
[error]



=== TEST 23: rocketmq nameserver list info in log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                             "rocketmq-logger": {
                                    "nameserver_list" :
                                      {
                                        "127.0.0.127":9876
                                      },
                                    "rocketmq_topic" : "test2",
                                    "producer_type": "sync",
                                    "key" : "key1",
                                    "batch_max_size": 1
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
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
        }
    }
--- request
GET /t
--- error_log_like eval
qr/create new rocketmq producer instance, nameserver_list: \[\{"port":9876,"host":"127.0.0.127"}]/
qr/failed to send data to rocketmq topic: .*, nameserver_list: \{"127.0.0.127":9876}/



=== TEST 24: delete plugin metadata, tests would fail if run rocketmq-logger-log-format.t and plugin metadata is added
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/rocketmq-logger',
                ngx.HTTP_DELETE,
                nil,
                [[{"action": "delete"}]])
        }
    }
--- request
GET /t
--- response_body

--- no_error_log
[error]



=== TEST 25: set route(id: 1,include_req_body = true,include_req_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" :
                                  {
                                    "127.0.0.1":9876
                                  },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_req_body": true,
                                "include_req_body_expr": [
                                    [
                                      "arg_name",
                                      "==",
                                      "qwerty"
                                    ]
                                ],
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
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



=== TEST 26: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log eval
qr/send data to rocketmq: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 27: hit route,expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to rocketmq: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 28: check log schema(include_req_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 rocketmq_topic = "test",
                 key = "key1",
                 nameserver_list = {
                    ["127.0.0.1"] = 3
                 },
                 include_req_body = true,
                 include_req_body_expr = {
                     {"bar", "<>", "foo"}
                 }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to validate the 'include_req_body_expr' expression: invalid operator '<>'
done
--- no_error_log
[error]



=== TEST 29: check log schema(include_resp_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 rocketmq_topic = "test",
                 key = "key1",
                 nameserver_list = {
                    ["127.0.0.1"] = 3
                 },
                 include_resp_body = true,
                 include_resp_body_expr = {
                     {"bar", "<!>", "foo"}
                 }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to validate the 'include_resp_body_expr' expression: invalid operator '<!>'
done
--- no_error_log
[error]



=== TEST 30: set route(id: 1,include_resp_body = true,include_resp_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" :
                                  {
                                    "127.0.0.1":9876
                                  },
                                "rocketmq_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_resp_body": true,
                                "include_resp_body_expr": [
                                    [
                                      "arg_name",
                                      "==",
                                      "qwerty"
                                    ]
                                ],
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
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



=== TEST 31: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log eval
qr/send data to rocketmq: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 32: hit route,expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to rocketmq: \{.*"body":"hello world\\n"/
--- wait: 2
