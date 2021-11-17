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

=== TEST 1: sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk-serverless")
            local ok, err = plugin.check_schema({api_host = "http://127.0.0.1:3233", service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: missing `api_host`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk-serverless")
            local ok, err = plugin.check_schema({service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
property "api_host" is required
--- no_error_log
[error]



=== TEST 3: wrong type for `api_host`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk-serverless")
            local ok, err = plugin.check_schema({api_host = 3233, service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
property "api_host" validation failed: wrong type: expected string, got number
--- no_error_log
[error]



=== TEST 4: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk-serverless": {
                                "api_host": "http://127.0.0.1:3233"
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP"
                                "namespace": "guest",
                                "action": "test"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: hit route (with GET request)
--- request
GET /hello
--- error_code: 405
--- no_error_log
[error]



=== TEST 6: hit route (with non-json format request body)
--- request
POST /hello
test=test
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- no_error_log
[error]



=== TEST 7: hit route (with correct request body)
--- request
POST /hello
{"name": "world"}
--- more_headers
Content-Type: application/json
--- response_body
{"hello":"world"}
--- no_error_log
[error]