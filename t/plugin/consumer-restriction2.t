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
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: create consumer group(group1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/group1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {}
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



=== TEST 2: create consumer group(group2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumer_groups/group2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {}
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



=== TEST 3: consumer jack1 with consumer group(group1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2019",
                            "password": "123456"
                        }
                    },
                    "group_id": "group1"
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



=== TEST 4: consumer jack2 with consumer group(group2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack2",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2020",
                            "password": "123456"
                        }
                    },
                    "group_id": "group2"
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



=== TEST 5: set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                "type": "consumer_group_id",
                                 "whitelist": [
                                     "group1"
                                 ]
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



=== TEST 6: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 7: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world



=== TEST 8: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_group_id is forbidden."}



=== TEST 9: set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "type": "consumer_group_id",
                                 "blacklist": [
                                     "group1"
                                 ],
                                 "rejected_msg": "request is forbidden"
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



=== TEST 10: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 11: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"request is forbidden"}



=== TEST 12: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world
