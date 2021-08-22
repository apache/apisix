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

=== TEST 1: update the broker_list via admin-api
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
                            "kafka_topic" : "test3",
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

            code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "kafka-logger": {
                            "broker_list" : {
                                "127.0.0.1": 19092
                            },
                            "kafka_topic" : "test3",
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
--- request
GET /t
--- timeout: 10
--- response
passed
--- wait: 5
--- error_log eval
[qr/"broker_list":\{"127.0.0.1":9092\}.*/,
qr/"broker_list":\{"127.0.0.1":19092\}.*/]
--- no_error_log eval
qr/not found topic/



=== TEST 2: update the broker_list by modifying the data in etcd
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
                            "kafka_topic" : "test3",
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

            local core = require("apisix.core")
            local res, err = core.etcd.set("/global_rules/1", core.json.decode([[{
                    "plugins": {
                        "kafka-logger": {
                            "broker_list" : {
                                "127.0.0.1": 19092
                            },
                            "kafka_topic" : "test3",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                    }
                }]]))
            if res.status >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            -- wait for sync
            ngx.sleep(0.6)

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
--- error_log eval
[qr/"broker_list":\{"127.0.0.1":9092\}.*/,
qr/"broker_list":\{"127.0.0.1":19092\}.*/]
--- no_error_log eval
qr/not found topic/
