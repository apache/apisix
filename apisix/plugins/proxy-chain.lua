#!/usr/bin/env perl
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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Create route with proxy-chain plugin configuration
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/test",
                                    "method": "POST"
                                }
                            ],
                            "token_header": "X-API-Key"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:]] .. ngx.var.server_port .. [[": 1
                        }
                    },
                    "uri": "/proxy-chain"
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



=== TEST 2: create mock service endpoint
--- config
    location /test {
        content_by_lua_block {
            -- Read the incoming request body
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            local cjson = require("cjson")

            -- Parse JSON body if available
            local data = {}
            if body and body ~= "" then
                local success, decoded = pcall(cjson.decode, body)
                if success then
                    data = decoded
                end
            end

            -- Add mock service response data to merge with original request
            data.service_response = "test_value"
            data.service_id = "service_1"
            data.processed_by = "mock_service"

            -- Return JSON response
            ngx.header['Content-Type'] = 'application/json'
            ngx.say(cjson.encode(data))
        }
    }
--- request
POST /test
{"original": "data"}
--- response_body_like
.*service_response.*



=== TEST 3: create upstream endpoint
--- config
    location /upstream {
        content_by_lua_block {
            -- This endpoint simulates the final upstream service
            ngx.req.read_body()
            local body = ngx.req.get_body_data()

            -- Return the received body to verify proxy-chain worked
            ngx.header['Content-Type'] = 'application/json'
            ngx.say('{"upstream_response": "received", "body": "' .. (body or "nil") .. '"}')
        }
    }
--- request
POST /upstream
--- response_body_like
.*upstream_response.*



=== TEST 4: test proxy-chain plugin - successful chaining
--- config
    location /t {
        content_by_lua_block {
            -- First create the route with proxy-chain plugin
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/test",
                                    "method": "POST"
                                }
                            ],
                            "token_header": "X-API-Key"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:]] .. ngx.var.server_port .. [[": 1
                        }
                    },
                    "uri": "/proxy-chain"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("Failed to create route: " .. body)
                return
            end

            -- Wait a moment for the route to be ready
            ngx.sleep(0.1)

            -- Now test the actual proxy-chain functionality
            local http = require("resty.http")
            local httpc = http.new()

            -- Make request to proxy-chain endpoint
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/proxy-chain", {
                method = "POST",
                body = '{"original_data": "test"}',
                headers = {
                    ["Content-Type"] = "application/json",
                    ["X-API-Key"] = "test-token"  -- Test token header
                }
            })

            if not res then
                ngx.status = 500
                ngx.say("Request failed: " .. (err or "unknown error"))
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like
.*service_response.*
--- no_error_log
[error]



=== TEST 5: add route for multiple services test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Create route that chains multiple services
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/test",
                                    "method": "POST"
                                },
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/test2",
                                    "method": "POST"
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:]] .. ngx.var.server_port .. [[": 1
                        }
                    },
                    "uri": "/proxy-chain-multi"
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



=== TEST 6: create second mock service
--- config
    location /test2 {
        content_by_lua_block {
            -- Second service in the chain - receives merged data from first service
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            local cjson = require("cjson")

            -- Parse the merged data from previous service
            local data = {}
            if body and body ~= "" then
                local success, decoded = pcall(cjson.decode, body)
                if success then
                    data = decoded
                end
            end

            -- Add additional data from second service
            data.second_service = "second_value"
            data.chain_step = 2
            data.final_processed = true

            -- Return merged response
            ngx.header['Content-Type'] = 'application/json'
            ngx.say(cjson.encode(data))
        }
    }
--- request
POST /test2
--- response_body_like
.*second_service.*



=== TEST 7: test multiple service chaining
--- config
    location /t {
        content_by_lua_block {
            -- Wait for route to be ready
            ngx.sleep(0.1)

            local http = require("resty.http")
            local httpc = http.new()

            -- Test chaining multiple services
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/proxy-chain-multi", {
                method = "POST",
                body = '{"initial": "data"}',
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            if not res then
                ngx.status = 500
                ngx.say("Request failed: " .. (err or "unknown error"))
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like
.*second_service.*
--- no_error_log
[error]



=== TEST 8: test invalid configuration - empty services array
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Test invalid configuration with empty services array
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": []
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/invalid"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400



=== TEST 9: test service error handling
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Create route with service that will fail (nonexistent endpoint)
            local code, body = t('/apisix/admin/routes/4',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/nonexistent",
                                    "method": "POST"
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:]] .. ngx.var.server_port .. [[": 1
                        }
                    },
                    "uri": "/error-test"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- Wait for route to be ready
            ngx.sleep(0.1)

            local http = require("resty.http")
            local httpc = http.new()

            -- Test error handling when service fails
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/error-test", {
                method = "POST",
                body = '{"test": "data"}',
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            ngx.status = res and res.status or 500
            ngx.say(res and res.body or "Request failed")
        }
    }
--- request
GET /t
--- error_code: 404



=== TEST 10: test without token header configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Test proxy-chain without token_header configuration
            local code, body = t('/apisix/admin/routes/5',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/test",
                                    "method": "POST"
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:]] .. ngx.var.server_port .. [[": 1
                        }
                    },
                    "uri": "/no-token-test"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local http = require("resty.http")
            local httpc = http.new()

            -- Test without any token headers
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/no-token-test", {
                method = "POST",
                body = '{"no_token": "test"}',
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            if not res then
                ngx.status = 500
                ngx.say("Request failed: " .. (err or "unknown error"))
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like
.*service_response.*
--- no_error_log
[error]
