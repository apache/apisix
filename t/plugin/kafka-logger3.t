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

=== TEST 1: set route with sasl_config to check if password is hidden in log
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



=== TEST 2: hit route, send data to kafka successfully
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- wait: 2
--- error_log eval
qr/\"password\":\"\*\*\*\*\"/
