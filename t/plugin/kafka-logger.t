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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

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
--- response_body
done



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
--- response_body
value should match only one schema, but matches none
done



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
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
done



=== TEST 4: api_version 2 for Kafka 4.x
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                kafka_topic = "test",
                brokers = {{host = "127.0.0.1", port = 9092}},
                api_version = 2,
            })
            if not ok then
                ngx.say("err: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 5: api_version 0 for Kafka < 0.10.0.0
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                kafka_topic = "test",
                brokers = {{host = "127.0.0.1", port = 9092}},
                api_version = 0,
            })
            if not ok then
                ngx.say("err: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 6: invalid api_version
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                kafka_topic = "test",
                brokers = {{host = "127.0.0.1", port = 9092}},
                api_version = 3,
            })
            if not ok then
                ngx.say("err: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
err: property "api_version" validation failed: expected 3 to be at most 2



=== TEST 7: set route(id: 1)
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



=== TEST 8: access
--- request
GET /hello
--- response_body
hello world
--- wait: 2
--- ignore_error_log



=== TEST 9: error log
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
--- error_log
failed to send data to Kafka topic
[error]
--- wait: 1



=== TEST 10: set route(meta_format = origin, include_req_body = true)
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
--- response_body
passed



=== TEST 11: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log
send data to kafka: GET /hello?ab=cd HTTP/1.1
host: localhost
content-length: 6
connection: close

abcdef
--- wait: 2



=== TEST 12: set route(meta_format = origin, include_req_body = false)
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
--- response_body
passed



=== TEST 13: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log
send data to kafka: GET /hello?ab=cd HTTP/1.1
host: localhost
content-length: 6
connection: close
--- wait: 2



=== TEST 14: set route(meta_format = default)
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
--- response_body
passed



=== TEST 15: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log_like eval
qr/send data to kafka: \{.*"upstream":"127.0.0.1:1980"/
--- wait: 2



=== TEST 16: set route(id: 1), missing key field
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



=== TEST 17: access, test key field is optional
--- request
GET /hello
--- response_body
hello world
--- wait: 2



=== TEST 18: set route(meta_format = default), missing key field
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
--- response_body
passed



=== TEST 19: hit route, report log to kafka
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log_like eval
qr/send data to kafka: \{.*"upstream":"127.0.0.1:1980"/
--- wait: 2



=== TEST 20: use the topic with 3 partitions
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
--- response_body
passed



=== TEST 21: report log to kafka by different partitions
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
--- timeout: 5s
--- ignore_response
--- error_log eval
[qr/partition_id: 1/,
qr/partition_id: 0/,
qr/partition_id: 2/]



=== TEST 22: report log to kafka by different partitions in async mode
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
--- timeout: 5s
--- ignore_response
--- error_log eval
[qr/partition_id: 1/,
qr/partition_id: 0/,
qr/partition_id: 2/]



=== TEST 23: set route with incorrect sasl_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins":{
                        "kafka-logger":{
                            "brokers":[
                            {
                                "host":"127.0.0.1",
                                "port":19094,
                                "sasl_config":{
                                    "mechanism":"PLAIN",
                                    "user":"admin",
                                    "password":"admin-secret2233"
                            }
                        }],
                            "kafka_topic":"test2",
                            "key":"key1",
                            "timeout":1,
                            "batch_max_size":1
                        }
                    },
                    "upstream":{
                        "nodes":{
                            "127.0.0.1:1980":1
                        },
                        "type":"roundrobin"
                    },
                    "uri":"/hello"
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



=== TEST 24: hit route, failed to send data to kafka
--- request
GET /hello
--- response_body
hello world
--- error_log
failed to do PLAIN auth with 127.0.0.1:19094: Authentication failed: Invalid username or password
--- wait: 2



=== TEST 25: set route with correct sasl_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins":{
                        "kafka-logger":{
                            "brokers":[
                            {
                                "host":"127.0.0.1",
                                "port":19094,
                                "sasl_config":{
                                    "mechanism":"PLAIN",
                                    "user":"admin",
                                    "password":"admin-secret"
                            }
                        }],
                            "kafka_topic":"test4",
                            "producer_type":"sync",
                            "key":"key1",
                            "timeout":1,
                            "batch_max_size":1,
                            "include_req_body": true
                        }
                    },
                    "upstream":{
                        "nodes":{
                            "127.0.0.1:1980":1
                        },
                        "type":"roundrobin"
                    },
                    "uri":"/hello"
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



=== TEST 26: hit route, send data to kafka successfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- no_error_log
[error]
--- wait: 2



=== TEST 27: Kafka 4.x with api_version=2 (verify compatibility)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "kafka-logger": {
                            "brokers": [{"host": "127.0.0.1", "port": 39092}],
                            "kafka_topic": "test-kafka4",
                            "api_version": 2,
                            "key": "key1",
                            "timeout": 3,
                            "batch_max_size": 1,
                            "producer_type": "sync"
                        }
                    },
                    "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                    "uri": "/hello"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 28: hit route, send data to Kafka 4.x successfully
--- request
GET /hello?kafka4=yes
--- response_body
hello world
--- error_log_like eval
qr/send data to kafka: \{.*"upstream":"127.0.0.1:1980"/
--- no_error_log
[error]
--- wait: 3



=== TEST 29: set route(batch_max_size = 2), check if prometheus is initialized properly
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
                                "batch_max_size": 2
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
--- response_body
passed



=== TEST 30: access
--- extra_yaml_config
plugins:
  - kafka-logger
--- request
GET /hello
--- response_body
hello world
--- wait: 2



=== TEST 31: create a service with kafka-logger and three routes bound to it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
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
                        }
                }]]
                )
            if code >= 300 then
                ngx.say("create service failed")
                return
            end
            for i = 1, 3 do
                local code, body = t('/apisix/admin/routes/' .. i,
                     ngx.HTTP_PUT,
                     string.format([[{
                        "uri": "/hello%d",
                        "service_id": "1"
                     }]], i)
                    )
                if code >= 300 then
                    ngx.say("create route failed")
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 32: hit three routes, should create batch processor only once
--- log_level: debug
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            for i = 1, 3 do
                local resp = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello" .. i)
                if not resp then
                    ngx.say("failed to request test server")
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- grep_error_log eval
qr/creating new batch processor with config.*/
--- grep_error_log_out eval
qr/creating new batch processor with config.*/
