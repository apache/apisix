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

=== TEST 1: set route with invalid host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_port": 1985,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4
                        }
                    },
                    "upstream": {
                        "type": "chash",
                        "key": "mqtt_client_id",
                        "nodes": [
                            {
                                "host": "loc",
                                "port": 1995,
                                "weight": 1
                            }
                        ]
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



=== TEST 2: hit route
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- error_log
failed to parse domain: loc, error:
--- timeout: 10



=== TEST 3: set upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "chash",
                    "key": "mqtt_client_id",
                    "nodes": [
                    {
                        "host": "0.0.0.0",
                        "port": 1995,
                        "weight": 1
                    },
                    {
                        "host": "127.0.0.1",
                        "port": 1995,
                        "weight": 1
                    }
                    ]
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



=== TEST 4: balance with mqtt_client_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_port": 1985,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 5
                        }
                    },
                    "upstream_id": 1
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



=== TEST 5: hit route with empty id
--- stream_request eval
"\x10\x0d\x00\x04\x4d\x51\x54\x54\x05\x02\x00\x3c\x00\x00\x00"
--- stream_response
hello world
--- grep_error_log eval
qr/(mqtt client id: \w+|proxy request to \S+)/
--- grep_error_log_out
proxy request to 127.0.0.1:1995



=== TEST 6: hit route with different client id, part 1
--- stream_request eval
"\x10\x0e\x00\x04\x4d\x51\x54\x54\x05\x02\x00\x3c\x00\x00\x01\x66"
--- stream_response
hello world
--- grep_error_log eval
qr/(mqtt client id: \w+|proxy request to \S+)/
--- grep_error_log_out
mqtt client id: f
proxy request to 0.0.0.0:1995



=== TEST 7: hit route with different client id, part 2
--- stream_request eval
"\x10\x0e\x00\x04\x4d\x51\x54\x54\x05\x02\x00\x3c\x00\x00\x01\x67"
--- stream_response
hello world
--- grep_error_log eval
qr/(mqtt client id: \w+|proxy request to \S+)/
--- grep_error_log_out
mqtt client id: g
proxy request to 127.0.0.1:1995
