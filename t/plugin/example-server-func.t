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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: set route: valid plugin server func
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "example-plugin": {
                                "i": 1,
                                "ip": "127.0.0.1",
                                "port": 1981,
                                "server_func": "server_port"
                            }
                        },
                        "uri": "/server_port"
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



=== TEST 2: hit route: valid plugin server addr
--- yaml_config
apisix:
    server_func_addr: "http://127.0.0.1:1981"
--- request
GET /server_port
--- response_headers
Server-Func-Response: 1981



=== TEST 3: hit route: server_func_addr with suffix
--- yaml_config
apisix:
    server_func_addr: "http://127.0.0.1:1981/"
--- request
GET /server_port
--- response_headers
Server-Func-Response: 1981



=== TEST 4: set route: invalid plugin server func
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "example-plugin": {
                                "i": 1,
                                "ip": "127.0.0.1",
                                "port": 1981,
                                "func_name": "invalid"
                            }
                        },
                        "uri": "/server_port"
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



=== TEST 5: hit route: invalid plugin server addr
--- yaml_config
apisix:
    server_func_addr: "http://127.0.0.1:9999"
--- request
GET /server_port
--- response_headers
Server-Func-Response: failed to request server func: connection refused



=== TEST 6: hit route: invalid plugin server func
--- yaml_config
apisix:
    server_func_addr: "http://127.0.0.1:1981"
--- request
GET /server_port
--- response_headers
Server-Func-Response: 404
