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
no_root_location();
no_shuffle();


run_tests;

__DATA__

=== TEST 1: set route(host + uri)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local script = t.read_file("t/script/script_test.lua")
            local data = {
                script = script,
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode(data))

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- no_error_log
[error]
--- error_log
string "route#1"
phase_func(): hit access phase
phase_func(): hit header_filter phase
phase_func(): hit body_filter phase
phase_func(): hit body_filter phase
phase_func(): hit log phase while



=== TEST 3: invalid script in route
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                script = "invalid script",
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode(data))

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to load 'script' string: [string \"invalid script\"]:1: '=' expected near 'script'"}
--- no_error_log
[error]



=== TEST 4: invalid script in service
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                script = "invalid script",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            local code, body = t.test('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                core.json.encode(data))

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to load 'script' string: [string \"invalid script\"]:1: '=' expected near 'script'"}
--- no_error_log
[error]
