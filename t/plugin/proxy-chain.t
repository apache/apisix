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

=== TEST 1: check plugin schema
--- config
    location /t {
        content_by_lua_block {
            -- Test basic schema validation for proxy-chain plugin
            local plugin = require("apisix.plugins.proxy-chain")
            local ok, err = plugin.check_schema({
                services = {
                    {
                        uri = "http://127.0.0.1:1999/test",
                        method = "POST"
                    }
                }
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed

=== TEST 2: check plugin schema (invalid)
--- config
    location /t {
        content_by_lua_block {
            -- Test schema validation with invalid configuration (empty services array)
            local plugin = require("apisix.plugins.proxy-chain")
            local ok, err = plugin.check_schema({
                services = {}
            })
            if not ok then
                ngx.say("failed as expected: ", err)
                return
            end
            ngx.say("should have failed")
        }
    }
--- request
GET /t
--- response_body_like
failed as expected.*

=== TEST 3: set route with proxy-chain plugin
--- config
    location /t {
        content_by_lua_block {
            -- Create a route with proxy-chain plugin configuration
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/mock-service",
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
                    "uri": "/test-proxy-chain"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed

=== TEST 4: create mock service
--- config
    location /mock-service {
        content_by_lua_block {
            -- Mock service that receives request and adds additional data
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            local cjson = require("cjson")

            -- Parse incoming JSON data
            local data = {}
            if body and body ~= "" then
                local success, decoded = pcall(cjson.decode, body)
                if success then
                    data = decoded
                end
            end

            -- Add mock response data to be merged
            data.mock_response = "added by mock service"
            data.processed = true

            -- Return merged JSON response
            ngx.header['Content-Type'] = 'application/json'
            ngx.say(cjson.encode(data))
        }
    }
--- request
POST /mock-service
{"test": "data"}
--- response_body_like
.*mock_response.*

=== TEST 5: create final upstream
--- config
    location /final-upstream {
        content_by_lua_block {
            -- Final upstream service that receives the merged data from proxy-chain
            ngx.req.read_body()
            local body = ngx.req.get_body_data()

            -- Return the received body to verify proxy-chain worked correctly
            ngx.header['Content-Type'] = 'application/json'
            ngx.say('{"final_response": "success", "received_body": "' .. (body or "empty") .. '"}')
        }
    }
--- request
POST /final-upstream
--- response_body_like
.*final_response.*

=== TEST 6: test proxy-chain functionality
--- config
    location /t {
        content_by_lua_block {
            -- Test the complete proxy-chain functionality
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-chain": {
                            "services": [
                                {
                                    "uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/mock-service",
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
                    "uri": "/final-upstream"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("Route creation failed: " .. body)
                return
            end

            -- Wait for route to be ready
            ngx.sleep(0.5)

            -- Make request to test proxy-chain functionality
            local http = require("resty.http")
            local httpc = http.new()

            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/final-upstream", {
                method = "POST",
                body = '{"original": "data"}',
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            if not res then
                ngx.status = 500
                ngx.say("Request failed: " .. (err or "unknown"))
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like
.*final_response.*
--- no_error_log
[error]
