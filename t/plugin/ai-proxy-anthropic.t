--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

use t::APISIX 'no_plan';
use Test::Nginx::Socket::Lua;

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = <<'EOF';
    server {
        listen 1999;

        location /v1/messages {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.req.read_body()
                local body = core.json.decode(ngx.req.get_body_data())

                -- 1. Required Header: x-api-key
                if ngx.var.http_x_api_key ~= "test-key" then
                    ngx.status = 401
                    ngx.say([[{"type":"error","error":{"type":"authentication_error","message":"invalid api key"}}]])
                    return
                end

                -- 2. Required Header: anthropic-version
                if ngx.var.http_anthropic_version ~= "2023-06-01" then
                    ngx.status = 400
                    ngx.say("missing anthropic-version")
                    return
                end

                -- 3. Required Parameter: max_tokens
                if not body.max_tokens then
                    ngx.status = 400
                    ngx.say("missing max_tokens")
                    return
                end

                -- 4. Validate Anthropic's native message structure
                --    Messages must have content as array with type field
                local msg = body.messages[1]
                if type(msg.content) ~= "table"
                   or msg.content[1].type ~= "text" then
                    ngx.status = 400
                    ngx.say("invalid anthropic message format")
                    return
                end

                -- 5. Return mock Anthropic response
                ngx.status = 200
                ngx.say([[
                {
                  "id": "msg_123",
                  "type": "message",
                  "role": "assistant",
                  "content": [
                    { "type": "text", "text": "Hello from Claude" }
                  ],
                  "stop_reason": "end_turn"
                }
                ]])
            }
        }
    }
EOF

    $block->set_value("http_config", $http_config);
});

__DATA__

=== TEST 1: Create route with Anthropic provider
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Create a route that directly exposes Anthropic's native endpoint
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "anthropic",
                            "api_key": "test-key",
                            "override": {
                                "endpoint": "http://127.0.0.1:1999/v1/messages"
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

            ngx.say("route created successfully")
        }
    }
--- response_body
route created successfully



=== TEST 2: Send Anthropic native format request
--- request
POST /v1/messages
{
  "model": "claude-3",
  "max_tokens": 128,
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Hello" }
      ]
    }
  ]
}
--- more_headers
x-api-key: test-key
anthropic-version: 2023-06-01
Content-Type: application/json
--- error_code: 200
--- response_body_like eval
qr/"type"\s*:\s*"message"/



=== TEST 3: Test Anthropic streaming response (SSE)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local res, err = httpc:request_uri("http://127.0.0.1:9080/v1/messages", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["x-api-key"] = "test-key",
                    ["anthropic-version"] = "2023-06-01",
                },
                body = [[{
                    "model": "claude-3",
                    "stream": true,
                    "max_tokens": 16,
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                { "type": "text", "text": "Hi" }
                            ]
                        }
                    ]
                }]]
            })

            if err then
                ngx.status = 500
                ngx.say("request failed: ", err)
                return
            end

            ngx.status = res.status
            ngx.say(res.body or "")
        }
    }
--- response_body_like eval
qr/message/



=== TEST 4: Test authentication error handling
--- request
POST /v1/messages
{
  "model": "claude-3",
  "max_tokens": 16,
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Hi" }
      ]
    }
  ]
}
--- more_headers
x-api-key: wrong-key
anthropic-version: 2023-06-01
Content-Type: application/json
--- error_code: 401
--- response_body_like
authentication_error



=== TEST 5: Test missing max_tokens parameter
--- request
POST /v1/messages
{
  "model": "claude-3",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Hello" }
      ]
    }
  ]
}
--- more_headers
x-api-key: test-key
anthropic-version: 2023-06-01
Content-Type: application/json
--- error_code: 400
--- response_body_like
missing max_tokens



=== TEST 6: Test missing anthropic-version header
--- request
POST /v1/messages
{
  "model": "claude-3",
  "max_tokens": 128,
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Hello" }
      ]
    }
  ]
}
--- more_headers
x-api-key: test-key
Content-Type: application/json
--- error_code: 400
--- response_body_like
missing anthropic-version

