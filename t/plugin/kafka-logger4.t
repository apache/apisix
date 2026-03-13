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

=== TEST 1: set route with correct sasl_config - SCRAM-SHA-256
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
                                "port":29094,
                                "sasl_config":{
                                    "mechanism":"SCRAM-SHA-256",
                                    "user":"admin",
                                    "password":"admin-secret"
                            }
                        }],
                            "kafka_topic":"test-scram-256",
                            "producer_type":"async",
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



=== TEST 2: hit route, send data to kafka successfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"route_id":"1"/
--- no_error_log
[error]
--- wait: 2



=== TEST 3: set route with incorrect password - SCRAM-SHA-256
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
                                "port":29094,
                                "sasl_config":{
                                    "mechanism":"SCRAM-SHA-256",
                                    "user":"admin",
                                    "password":"admin-secrets"
                            }
                        }],
                            "kafka_topic":"test-scram-256",
                            "producer_type":"async",
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



=== TEST 4: hit route, send data to kafka unsuccessfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log
Authentication failed during authentication due to invalid credentials with SASL mechanism SCRAM-SHA-256
--- wait: 2



=== TEST 5: set route with correct sasl_config - SCRAM-SHA-512
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
                                "port":29094,
                                "sasl_config":{
                                    "mechanism":"SCRAM-SHA-512",
                                    "user":"admin",
                                    "password":"admin-secret"
                            }
                        }],
                            "kafka_topic":"test-scram-512",
                            "producer_type":"async",
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



=== TEST 6: hit route, send data to kafka successfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"route_id":"1"/
--- no_error_log
[error]
--- wait: 2



=== TEST 7: set route with incorrect password - SCRAM-SHA-512
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
                                "port":29094,
                                "sasl_config":{
                                    "mechanism":"SCRAM-SHA-512",
                                    "user":"admin",
                                    "password":"admin-secrets"
                            }
                        }],
                            "kafka_topic":"test-scram-256",
                            "producer_type":"async",
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



=== TEST 8: hit route, send data to kafka unsuccessfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log
Authentication failed during authentication due to invalid credentials with SASL mechanism SCRAM-SHA-512
--- wait: 2
