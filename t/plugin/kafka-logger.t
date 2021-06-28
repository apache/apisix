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
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                 kafka_topic = "test",
                 key = "key1",
                 broker_list = {
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



=== TEST 2: missing broker list
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({kafka_topic = "test", key= "key1"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "broker_list" is required
done
--- no_error_log
[error]



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                broker_list = {
                    ["127.0.0.1"] = 3000
                },
                timeout = "10",
                kafka_topic ="test",
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
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
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
                                 "kafka-logger": {
                                    "broker_list" :
                                      {
                                        "127.0.0.1":9092
                                      },
                                    "kafka_topic" : "test2",
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
                             "kafka-logger": {
                                    "broker_list" :
                                      {
                                        "127.0.0.1":9092,
                                        "127.0.0.1":9093
                                      },
                                    "kafka_topic" : "test2",
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
                                "kafka-logger": {
                                    "broker_list" :
                                      {
                                        "127.0.0.1":9092,
                                        "127.0.0.1":9093
                                      },
                                    "kafka_topic" : "test2",
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
failed to send data to Kafka topic
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
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
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



=== TEST 8: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log
send data to kafka: GET /hello?ab=cd HTTP/1.1
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
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
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



=== TEST 10: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log
send data to kafka: GET /hello?ab=cd HTTP/1.1
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
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
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



=== TEST 12: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log_like eval
qr/send data to kafka: \{.*"upstream":"127.0.0.1:1980"/
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
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
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
                                 "kafka-logger": {
                                    "broker_list" :
                                      {
                                        "127.0.0.1":9092
                                      },
                                    "kafka_topic" : "test2",
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
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
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



=== TEST 16: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log_like eval
qr/send data to kafka: \{.*"upstream":"127.0.0.1:1980"/
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
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1": 9092
                                },
                                "kafka_topic" : "test3",
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



=== TEST 18: report log to kafka by different partitions
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1": 9092
                                },
                                "kafka_topic" : "test3",
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
[qr/partition_id: 1/,
qr/partition_id: 0/,
qr/partition_id: 2/]



=== TEST 19: report log to kafka by different partitions in async mode
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1": 9092
                                },
                                "kafka_topic" : "test3",
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
[qr/partition_id: 1/,
qr/partition_id: 0/,
qr/partition_id: 2/]
