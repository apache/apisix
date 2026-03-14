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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6725;

            default_type 'text/event-stream';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local header_auth = ngx.req.get_headers()["authorization"]
                    if header_auth ~= "Bearer token" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.header["Content-Type"] = "text/event-stream"

                    local test_type = ngx.req.get_headers()["test-type"]

                    if test_type == "split_event" then
                        ngx.say([[data: {"choices":[{"delta":{"content":"He]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[llo"},"index":0}]}\n\n]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[data: {"choices":[{"delta":{"content":" World"},"index":0}]}]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[data: [DONE]\n\n]])
                        return
                    end

                    if test_type == "split_event_multiline" then
                        ngx.say([[data: {"choices":[{"delta":{"content":"First]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[ line]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([["},"index":0}]}\n\ndata: {"choices":[{"delta":{"content":"Second"},"index":0}]}\n\n]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[data: [DONE]\n\n]])
                        return
                    end

                    if test_type == "split_across_chunks" then
                        ngx.say([[data: {"choices":[{"delta":{"content":"A]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[B]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[C"},"index":0}]}\n\ndata: {"choices]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[:[{"delta":{"content":"D"},"index":0}]}\n\n]])
                        ngx.flush(true)
                        ngx.sleep(0.01)
                        ngx.say([[data: [DONE]\n\n]])
                        return
                    end

                    ngx.say([[data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}\n\n]])
                    ngx.flush(true)
                    ngx.sleep(0.01)
                    ngx.say([[data: [DONE]\n\n]])
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with stream = true (SSE)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0,
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://localhost:6725"
                            },
                            "ssl_verify": false
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
--- response_body
passed



=== TEST 2: test SSE event split across chunks
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["test-type"] = "split_event",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ]
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader()
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            local full_response = table.concat(final_res, "")
            if string.find(full_response, "He") and string.find(full_response, "llo") and string.find(full_response, "World") and string.find(full_response, "DONE") then
                ngx.say("SSE split event handled correctly")
            else
                ngx.say("Failed to handle SSE split event: ", full_response)
            end
        }
    }
--- response_body
SSE split event handled correctly



=== TEST 3: test SSE multiple events split across chunks
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["test-type"] = "split_event_multiline",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ]
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader()
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            local full_response = table.concat(final_res, "")
            if string.find(full_response, "First") and string.find(full_response, "line") and string.find(full_response, "Second") then
                ngx.say("SSE multiline events handled correctly")
            else
                ngx.say("Failed to handle SSE multiline events: ", full_response)
            end
        }
    }
--- response_body
SSE multiline events handled correctly



=== TEST 4: test SSE event split in middle of data field
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["test-type"] = "split_across_chunks",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ]
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader()
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            local full_response = table.concat(final_res, "")
            if string.find(full_response, "A") and string.find(full_response, "B") and string.find(full_response, "C") and string.find(full_response, "D") and string.find(full_response, "DONE") then
                ngx.say("SSE event split in data field handled correctly")
            else
                ngx.say("Failed to handle SSE event split in data field: ", full_response)
            end
        }
    }
--- response_body
SSE event split in data field handled correctly
