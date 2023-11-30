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

=== TEST 1: required_acks, matches none of the enum values
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                broker_list = {
                    ["127.0.0.1"] = 3000
                },
                required_acks = 10,
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
property "required_acks" validation failed: matches none of the enum values
done



=== TEST 2: report log to kafka, with required_acks(1, -1)
--- config
location /t {
    content_by_lua_block {
        local data = {
            {
                input = {
                    plugins = {
                        ["kafka-logger"] = {
                            broker_list = {
                                ["127.0.0.1"] = 9092
                            },
                            kafka_topic = "test2",
                            producer_type = "sync",
                            timeout = 1,
                            batch_max_size = 1,
                            required_acks = 1,
                            meta_format = "origin",
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello",
                },
            },
            {
                input = {
                    plugins = {
                        ["kafka-logger"] = {
                            broker_list = {
                                ["127.0.0.1"] = 9092
                            },
                            kafka_topic = "test2",
                            producer_type = "sync",
                            timeout = 1,
                            batch_max_size = 1,
                            required_acks = -1,
                            meta_format = "origin",
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello",
                },
            },
        }

        local t = require("lib.test_admin").test
        local err_count = 0
        for i in ipairs(data) do
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, data[i].input)

            if code >= 300 then
                err_count = err_count + 1
            end
            ngx.print(body)

            t('/hello', ngx.HTTP_GET)
        end

        assert(err_count == 0)
    }
}
--- error_log
send data to kafka: GET /hello
send data to kafka: GET /hello
send data to kafka: GET /hello



=== TEST 3: update the broker_list and cluster_name, generate different kafka producers
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

            code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "kafka-logger": {
                            "broker_list" : {
                                "127.0.0.1": 9092
                            },
                            "kafka_topic" : "test2",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false,
                            "cluster_name": 1
                        }
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

            code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "kafka-logger": {
                            "broker_list" : {
                                "127.0.0.1": 19092
                            },
                            "kafka_topic" : "test4",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false,
                            "cluster_name": 2
                        }
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
--- timeout: 10
--- response
passed
--- wait: 5
--- error_log
phase_func(): kafka cluster name 1, broker_list[1] port 9092
phase_func(): kafka cluster name 2, broker_list[1] port 19092
--- no_error_log eval
qr/not found topic/



=== TEST 4: use the topic that does not exist on kafka(even if kafka allows auto create topics, first time push messages to kafka would got this error)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "kafka-logger": {
                            "broker_list" : {
                                "127.0.0.1": 9092
                            },
                            "kafka_topic" : "undefined_topic",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
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
--- timeout: 5
--- response
passed
--- error_log eval
qr/not found topic, retryable: true, topic: undefined_topic, partition_id: -1/



=== TEST 5: check broker_list via schema
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    input = {
                        broker_list = {},
                        kafka_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        broker_list = {
                            ["127.0.0.1"] = "9092"
                        },
                        kafka_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        broker_list = {
                            ["127.0.0.1"] = 0
                        },
                        kafka_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        broker_list = {
                            ["127.0.0.1"] = 65536
                        },
                        kafka_topic = "test",
                        key= "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                            }
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                port = 9092,
                            }
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = "9093",
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 0,
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 65536,
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9093,
                                sasl_config = {
                                    mechanism = "INVALID",
                                    user = "admin",
                                    password = "admin-secret",
                                },
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9093,
                                sasl_config = {
                                    user = "admin",
                                },
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
                {
                    input = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9093,
                                sasl_config = {
                                    password = "admin-secret",
                                },
                            },
                        },
                        kafka_topic = "test",
                        key = "key1",
                    },
                },
            }

            local plugin = require("apisix.plugins.kafka-logger")

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
--- response_body
property "broker_list" validation failed: expect object to have at least 1 properties
property "broker_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): wrong type: expected integer, got string
property "broker_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): expected 0 to be at least 1
property "broker_list" validation failed: failed to validate 127.0.0.1 (matching ".*"): expected 65536 to be at most 65535
property "brokers" validation failed: expect array to have at least 1 items
property "brokers" validation failed: failed to validate item 1: property "port" is required
property "brokers" validation failed: failed to validate item 1: property "host" is required
property "brokers" validation failed: failed to validate item 1: property "port" validation failed: wrong type: expected integer, got string
property "brokers" validation failed: failed to validate item 1: property "port" validation failed: expected 0 to be at least 1
property "brokers" validation failed: failed to validate item 1: property "port" validation failed: expected 65536 to be at most 65535
property "brokers" validation failed: failed to validate item 1: property "sasl_config" validation failed: property "mechanism" validation failed: matches none of the enum values
property "brokers" validation failed: failed to validate item 1: property "sasl_config" validation failed: property "password" is required
property "brokers" validation failed: failed to validate item 1: property "sasl_config" validation failed: property "user" is required



=== TEST 6: kafka brokers info in log
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
                                        "127.0.0.127":9092
                                      },
                                    "kafka_topic" : "test2",
                                    "producer_type": "sync",
                                    "key" : "key1",
                                    "batch_max_size": 1,
                                    "cluster_name": 10
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
--- error_log_like eval
qr/create new kafka producer instance, brokers: \[\{"port":9092,"host":"127.0.0.127"}]/
qr/failed to send data to Kafka topic: .*, brokers: \{"127.0.0.127":9092}/



=== TEST 7: set route(id: 1,include_req_body = true,include_req_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
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

--- response_body
passed



=== TEST 8: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 9: hit route,expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 10: check log schema(include_req_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                 kafka_topic = "test",
                 key = "key1",
                 broker_list = {
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
--- response_body
failed to validate the 'include_req_body_expr' expression: invalid operator '<>'
done



=== TEST 11: check log schema(include_resp_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                 kafka_topic = "test",
                 key = "key1",
                 broker_list = {
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
--- response_body
failed to validate the 'include_resp_body_expr' expression: invalid operator '<!>'
done



=== TEST 12: set route(id: 1,include_resp_body = true,include_resp_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
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

--- response_body
passed



=== TEST 13: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 14: hit route,expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to kafka: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 15: multi level nested expr conditions
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local kafka = {
                 kafka_topic = "test2",
                 key = "key1",
                 batch_max_size = 1,
                 broker_list = {
                    ["127.0.0.1"] = 9092
                 },
                 timeout = 3,
                 include_req_body = true,
                 include_req_body_expr = {
                    {"request_length", "<", 1054},
                    {"arg_name", "in", {"qwerty", "asdfgh"}}
                 },
                 include_resp_body = true,
                 include_resp_body_expr = {
                    {"http_content_length", "<", 1054},
                    {"arg_name", "in", {"qwerty", "zxcvbn"}}
                 }
            }
            local plugins = {}
            plugins["kafka-logger"] = kafka
            local data = {
                plugins = plugins
            }
            data.upstream = {
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1980"] = 1
                }
            }
            data.uri = "/hello"
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 core.json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: hit route, req_body_expr and resp_body_expr both eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
[qr/send data to kafka: \{.*"body":"abcdef"/,
qr/send data to kafka: \{.*"body":"hello world\\n"/]
--- wait: 2



=== TEST 17: hit route, req_body_expr eval success, resp_body_expr both eval failed
--- request
POST /hello?name=asdfgh
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- no_error_log eval
qr/send data to kafka: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 18: hit route, req_body_expr eval failed, resp_body_expr both eval success
--- request
POST /hello?name=zxcvbn
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"hello world\\n"/
--- no_error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 19: hit route, req_body_expr eval success, resp_body_expr both eval failed
--- request
POST /hello?name=xxxxxx
abcdef
--- response_body
hello world
--- no_error_log eval
[qr/send data to kafka: \{.*"body":"abcdef"/,
qr/send data to kafka: \{.*"body":"hello world\\n"/]
--- wait: 2



=== TEST 20: update route(id: 1,include_req_body = true,include_req_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "brokers" :
                                  [{
                                    "host":"127.0.0.1",
                                    "port": 9092
                                  }],
                                "kafka_topic" : "test2",
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

--- response_body
passed



=== TEST 21: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 22: setup route with meta_refresh_interval
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "brokers" :
                                  [{
                                    "host":"127.0.0.1",
                                    "port": 9092
                                  }],
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_refresh_interval": 1,
                                "batch_max_size": 1,
                                "include_req_body": true
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

--- response_body
passed



=== TEST 23: hit route, send data to kafka successfully
--- request
POST /hello
abcdef
--- response_body
hello world
--- no_error_log
[error]
--- error_log eval
qr/send data to kafka: \{.*"body":"abcdef"/
--- wait: 2
