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


my $resp_file = 't/assets/ai-proxy-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);

print "Hello, World!\n";
print $resp;


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

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

                    local test_type = ngx.req.get_headers()["test-type"]
                    if test_type == "options" then
                        if body.foo == "bar" then
                            ngx.status = 200
                            ngx.print("options works")
                        else
                            ngx.status = 500
                            ngx.say("model options feature doesn't work")
                        end
                        return
                    end

                    if test_type == "header_forwarding" then
                        ngx.say(json.encode(ngx.req.get_headers()))
                        return
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end

                        if body.messages[1].content == "write an SQL query to get all rows from student table" then
                            ngx.print("SELECT * FROM STUDENTS")
                            return
                        end

                        ngx.status = 200
                        ngx.say([[$resp]])
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }

            location /v1/embeddings {
                content_by_lua_block {
                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("unsupported request method: ", ngx.req.get_method())
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    if header_auth ~= "Bearer token" then
                        ngx.status = 401
                        ngx.say("unauthorized")
                        return
                    end

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    local json = require("cjson.safe")
                    body, err = json.decode(body)
                    if err then
                        ngx.status = 400
                        ngx.say("failed to get request body: ", err)
                    end

                    if body.model ~= "text-embedding-ada-002" then
                        ngx.status = 400
                        ngx.say("unsupported model: ", body.model)
                        return
                    end

                    if body.encoding_format ~= "float" then
                        ngx.status = 400
                        ngx.say("unsupported encoding format: ", body.encoding_format)
                        return
                    end

                    ngx.status = 200
                    ngx.say([[
                        {
                          "object": "list",
                          "data": [
                            {
                              "object": "embedding",
                              "embedding": [
                                0.0023064255,
                                -0.009327292,
                                -0.0028842222
                              ],
                              "index": 0
                            }
                          ],
                          "model": "text-embedding-ada-002",
                          "usage": {
                            "prompt_tokens": 8,
                            "total_tokens": 8
                          }
                        }
                    ]])
                }
            }

            location /v1/responses {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                        return
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    if header_auth ~= "Bearer token" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    if not body then
                        ngx.status = 400
                        ngx.say("empty body")
                        return
                    end

                    body, err = json.decode(body)
                    if not body then
                        ngx.status = 400
                        ngx.say("bad json: ", err)
                        return
                    end

                    -- Responses API should NOT have stream_options
                    if body.stream_options then
                        ngx.status = 400
                        ngx.say(json.encode({
                            error = {
                                message = "Unrecognized request argument supplied: stream_options",
                                type = "invalid_request_error",
                            }
                        }))
                        return
                    end

                    -- Validate it looks like a Responses API request
                    if not body.input then
                        ngx.status = 400
                        ngx.say(json.encode({ error = "missing input field" }))
                        return
                    end

                    ngx.status = 200
                    ngx.say(json.encode({
                        id = "resp_abc123",
                        object = "response",
                        created_at = 1723780938,
                        model = body.model or "gpt-4o",
                        output = {
                            {
                                type = "message",
                                role = "assistant",
                                content = {
                                    { type = "output_text", text = "1 + 1 = 2." }
                                },
                            }
                        },
                        usage = {
                            input_tokens = 10,
                            output_tokens = 5,
                            total_tokens = 15,
                        }
                    }))
                }
            }

            location /random {
                content_by_lua_block {
                    ngx.print("path override works")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
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



=== TEST 4: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 401
--- response_body
Unauthorized



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



=== TEST 6: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
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
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 9: wrong JSON in request body should give error
--- request
GET /anything
{}"messages": [ { "role": "system", "cont
--- error_code: 400
--- response_body
{"message":"could not get parse JSON request body: Expected the end but found T_STRING at character 3"}



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
                                "endpoint": "http://localhost:6724"
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
                }
            )

            ngx.status = code
            ngx.say(actual_body)

        }
    }
--- error_code: 200
--- response_body
options works



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
                                "endpoint": "http://localhost:6724/random"
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
--- response_body
path override works



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
                                "endpoint": "http://localhost:7737"
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

            ngx.print(#final_res .. final_res[6])
        }
    }
--- response_body eval
qr/6data: \[DONE\]\n\n/



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
                                "endpoint": "http://localhost:6724/v1/embeddings"
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
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
test-type: header_forwarding
--- error_code: 200
--- response_body eval
qr/"x-request-id":"[\d\w-]+"/



=== TEST 23: send request with Authorization header
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer wrong token
--- error_code: 200



=== TEST 24b: Accept-Encoding header should be stripped before forwarding to provider
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



=== TEST 26: Responses API - should NOT inject stream_options
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "stream": false }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body_like eval
qr/resp_abc123/



=== TEST 27: Responses API with stream=true should NOT inject stream_options
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "stream": true }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- no_error_log
[error]



=== TEST 28: Responses API with instructions field
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?", "instructions": "You are a math tutor", "stream": false }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body_like eval
qr/resp_abc123/



=== TEST 29: Chat Completions still works after Responses API support (regression)
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
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
                                "endpoint": "http://localhost:7737"
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
--- http_config
    server {
        server_name openai_sse_multi;
        listen 7738;

        default_type 'text/event-stream';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"
                -- All events sent in a single write (one chunk)
                local all = 'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"content":"hello"},"index":0,"finish_reason":null}],"usage":null}\n\n'
                    .. 'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"content":" world"},"index":0,"finish_reason":null}],"usage":null}\n\n'
                    .. 'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{},"index":0,"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}\n\n'
                    .. 'data: [DONE]\n\n'
                ngx.print(all)
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



=== TEST 34: Responses API non-streaming passthrough - token usage extracted
--- request
POST /v1/responses
{ "model": "gpt-4o", "input": "What is 1+1?" }
--- more_headers
Authorization: Bearer token
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
                                "endpoint": "http://localhost:7739"
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
--- http_config
    server {
        server_name openai_responses_sse;
        listen 7739;

        default_type 'text/event-stream';

        location /v1/responses {
            content_by_lua_block {
                local json = require("cjson.safe")
                ngx.header["Content-Type"] = "text/event-stream"

                ngx.print("event: response.output_text.delta\ndata: " .. json.encode({type="response.output_text.delta", delta="Hello"}) .. "\n\n")
                ngx.flush(true)
                ngx.sleep(0.05)

                ngx.print("event: response.output_text.delta\ndata: " .. json.encode({type="response.output_text.delta", delta=" world"}) .. "\n\n")
                ngx.flush(true)
                ngx.sleep(0.05)

                ngx.print("event: response.completed\ndata: " .. json.encode({type="response.completed", response={usage={input_tokens=10, output_tokens=5, total_tokens=15}}}) .. "\n\n")
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
                endpoint = "http://localhost:6724/v1/chat/completions?extra=value",
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
