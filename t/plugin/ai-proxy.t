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


BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

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
});

run_tests();

__DATA__

=== TEST 1: minimal viable configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "openai",
                options = {
                    model = "gpt-4",
                },
                auth = {
                    header = {
                        some_header = "some_value"
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: unsupported provider
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "some-unique",
                options = {
                    model = "gpt-4",
                },
                auth = {
                    header = {
                        some_header = "some_value"
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/.*property "provider" validation failed: matches none of the enum values.*/



=== TEST 3: set route with wrong auth header
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
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "options": {
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 4: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 401
--- error_code: 401



=== TEST 5: set route with right auth header
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
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 6: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 7: send request with empty body
--- request
POST /anything
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body_chomp
failed to get request body: request body is empty



=== TEST 8: send request with wrong method (GET) should work
--- request
GET /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 9: wrong JSON in request body should give error
--- request
GET /anything
{}"messages": [ { "role": "system", "cont
--- error_code: 400
--- response_body
{"message":"could not parse JSON request body: Expected the end but found T_STRING at character 3"}



=== TEST 10: content-type should be JSON
--- request
POST /anything
prompt%3Dwhat%2520is%25201%2520%252B%25201
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body chomp
unsupported content-type: application/x-www-form-urlencoded, only application/json is supported



=== TEST 11: model options being merged to request body
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
                                "model": "some-model",
                                "foo": "bar",
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "system", "content": "You are a mathematician" },
                        { "role": "user", "content": "What is 1+1?" }
                    ]
                }]],
                nil,
                {
                    ["test-type"] = "options",
                    ["Content-Type"] = "application/json",
                    ["X-AI-Fixture"] = "openai/chat-basic.json",
                }
            )

            ngx.status = code
            ngx.say(actual_body)

        }
    }
--- error_code: 200
--- response_body_like eval
qr/chat\.completion/



=== TEST 12: override path
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
                            "model": "some-model",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "foo": "bar",
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/random"
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "system", "content": "You are a mathematician" },
                        { "role": "user", "content": "What is 1+1?" }
                    ]
                }]],
                nil,
                {
                    ["test-type"] = "path",
                    ["Content-Type"] = "application/json",
                }
            )

            ngx.status = code
            ngx.say(actual_body)

        }
    }
--- response_body_like eval
qr/return by random endpoint/



=== TEST 13: set route with stream = true (SSE)
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
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 14: test is SSE works as expected
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
                    ["X-AI-Fixture"] = "openai/chat-streaming.sse",
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
                local chunk, err = res.body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            local body = table.concat(final_res, "")
            local has_done = body:find("data: %[DONE%]")
            local has_hello = body:find('"content":"Hello"', 1, true)
            if has_done and has_hello then
                ngx.say("SSE stream received successfully")
            else
                ngx.say("FAIL: SSE content missing")
            end
        }
    }
--- response_body
SSE stream received successfully



=== TEST 15: proxy embedding endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/embeddings",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "text-embedding-ada-002",
                                "encoding_format": "float"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/embeddings"
                            }
                        }
                    }
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
--- response_body
passed



=== TEST 16: send request to embedding api
--- request
POST /embeddings
{
    "input": "The food was delicious and the waiter..."
}
--- more_headers
X-AI-Fixture: openai/embeddings-list.json
--- error_code: 200
--- response_body_like eval
qr/.*text-embedding-ada-002*/



=== TEST 17: proxy to a http endpoint without explicit port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/post",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://httpbin.local:8280/post"
                            }
                        }
                    }
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
--- response_body
passed



=== TEST 18: send request to /post api should work
--- request
POST /post
{"messages": [{"role": "user", "content": "hello"}]}
--- error_code: 200



=== TEST 19: set route with right auth header
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
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
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



=== TEST 20: send request
--- http_config
    server {
        server_name openai;
        listen 6724;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                local json = require("cjson.safe")
                ngx.say(json.encode(ngx.req.get_headers()))
            }
        }
    }
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
test-type: header_forwarding
--- error_code: 200
--- response_body eval
qr/"test-type":"header_forwarding"/



=== TEST 21: set route with right auth header
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
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false
                        },
                        "request-id": {
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



=== TEST 22: send request
--- http_config
    server {
        server_name openai;
        listen 6724;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                local json = require("cjson.safe")
                ngx.say(json.encode(ngx.req.get_headers()))
            }
        }
    }
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
test-type: header_forwarding
--- error_code: 200
--- response_body eval
qr/"x-request-id":"[\d\w-]+"/



=== TEST 23: send request with Authorization header
--- http_config
    server {
        server_name openai;
        listen 6724;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.status = 200
                ngx.say("{}")
            }
        }
    }
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer wrong token
--- error_code: 200



=== TEST 24b: Accept-Encoding header should be stripped before forwarding to provider
--- http_config
    server {
        server_name openai;
        listen 6724;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                local json = require("cjson.safe")
                ngx.say(json.encode(ngx.req.get_headers()))
            }
        }
    }
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
test-type: header_forwarding
Accept-Encoding: gzip, deflate
--- error_code: 200
--- response_body_unlike eval
qr/accept-encoding/



=== TEST 25: Responses API - set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uris": ["/anything", "/v1/responses"],
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 26: Responses API - should NOT inject stream_options
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "stream": false }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/responses-basic.json
--- error_code: 200
--- response_body_like eval
qr/resp_abc123/



=== TEST 27: Responses API with stream=true should NOT inject stream_options
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "stream": true }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/responses-basic.json
--- error_code: 200
--- no_error_log
[error]



=== TEST 28: Responses API with instructions field
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "instructions": "You are a math tutor", "stream": false }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/responses-basic.json
--- error_code: 200
--- response_body_like eval
qr/resp_abc123/



=== TEST 29: Chat Completions still works after Responses API support (regression)
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 30: set route for fragmented SSE test
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
                                "endpoint": "http://localhost:7738"
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



=== TEST 31: fragmented SSE - one event split across two TCP chunks
--- http_config
    server {
        server_name openai_sse_fragmented;
        listen 7738;

        default_type 'text/event-stream';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"
                -- First chunk: the first half of a valid SSE event (cut mid-JSON)
                local part1 = 'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
                -- Second chunk: the rest of the event + usage event + DONE
                local part2 = '"choices":[{"delta":{"content":"hi"},"index":0,"finish_reason":null}],"usage":null}\n\n'
                    .. 'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{},"index":0,"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}\n\n'
                    .. 'data: [DONE]\n\n'
                ngx.print(part1)
                ngx.flush(true)
                ngx.sleep(0.05)
                ngx.print(part2)
                ngx.flush(true)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

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

            local res, err = httpc:request({
                method = "POST",
                headers = { ["Content-Type"] = "application/json" },
                path = "/anything",
                body = [[{"messages": [{"role": "user", "content": "hi"}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            -- Drain the response
            while true do
                local chunk, err = res.body_reader()
                if err or not chunk then break end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
got token usage from ai service:
--- no_error_log
[error]



=== TEST 32: multiple SSE events in a single chunk
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
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")
            local httpc = http.new()

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

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["X-AI-Fixture"] = "openai/chat-multi-chunk.sse",
                },
                path = "/anything",
                body = [[{"messages": [{"role": "user", "content": "hi"}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            -- Drain the response
            while true do
                local chunk, err = res.body_reader()
                if err or not chunk then break end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
got token usage from ai service:
--- no_error_log
[error]



=== TEST 33: set route for Responses API non-streaming test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uris": ["/anything", "/v1/responses"],
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 34: Responses API non-streaming passthrough - token usage extracted
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?" }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/responses-basic.json
--- error_code: 200
--- response_body_like eval
qr/resp_abc123/
--- error_log
got token usage from ai service:
--- no_error_log
[error]



=== TEST 35: set route for Responses API streaming test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uris": ["/anything", "/v1/responses"],
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4o",
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
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



=== TEST 36: Responses API streaming passthrough - token usage extracted from response.completed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

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

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["X-AI-Fixture"] = "openai/responses-streaming.sse",
                },
                path = "/v1/responses",
                body = [[{"input": "hello", "model": "gpt-4o", "stream": true}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            -- Drain the response
            while true do
                local chunk, err = res.body_reader()
                if err or not chunk then break end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
got token usage from ai service:
--- no_error_log
[error]



=== TEST 37: auth.query should not be mutated across requests when endpoint has query params
--- config
    location /t {
        content_by_lua_block {
            local base = require("apisix.plugins.ai-providers.base")
            local core = require("apisix.core")

            local auth_query = {["api-version"] = "2024-01-01"}

            local provider = base.new({
                capabilities = {},
            })

            local ctx = {
                var = {},
                ai_client_protocol = "openai-chat",
            }
            local conf = { ssl_verify = false }
            local opts = {
                endpoint = "http://127.0.0.1:1980/v1/chat/completions?extra=value",
                auth = { query = auth_query, header = { Authorization = "Bearer token" } },
                conf = {},
            }

            provider:build_request(ctx, conf, {messages = {{role="user", content="hi"}}}, opts)
            provider:build_request(ctx, conf, {messages = {{role="user", content="hi"}}}, opts)

            if auth_query["extra"] then
                ngx.say("FAIL: auth.query was mutated, extra=" .. auth_query["extra"])
            else
                ngx.say("OK: auth.query is clean")
            end
        }
    }
--- response_body
OK: auth.query is clean
