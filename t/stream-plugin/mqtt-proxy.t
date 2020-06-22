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

=== TEST 1: set route
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
                            "protocol_level": 4,
                            "upstream": {
                                "ip": "127.0.0.1",
                                "port": 1995
                            }
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



=== TEST 2: invalid header
--- stream_enable
--- stream_request eval
mmm
--- error_log
Received unexpected MQTT packet type+flags



=== TEST 3: hit route
--- stream_enable
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- stream_response
hello world
--- no_error_log
[error]



=== TEST 4: set route (wrong server port)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_port": 2000,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4,
                            "upstream": {
                                "ip": "127.0.0.1",
                                "port": 1995
                            }
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



=== TEST 5: failed to match route
--- stream_enable
--- stream_request eval
"\x10\x0f"
--- stream_response
receive stream response error: connection reset by peer
--- error_log
receive stream response error: connection reset by peer
--- error_log
match(): not hit any route
