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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy
  - ai-proxy-multi
  - ai-request-rewrite
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        # Stand-in for api.edenai.run. Only the /v3/ prefix exists, so a wrong
        # default path is a 404 instead of a silently accepted request. Every
        # reply carries the request the upstream actually received (path,
        # method, auth header) plus the raw body in the OpenAI chat shape, so
        # tests can assert exactly what ai-proxy sent.
        server {
            server_name echo-edenai;
            listen 6752;
            default_type 'application/json';

            location /v3/ {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data() or ""
                    local hdrs = ngx.req.get_headers()
                    ngx.status = 200
                    ngx.say(json.encode({
                        id = "echo-1",
                        object = "chat.completion",
                        model = "echo",
                        choices = {{
                            index = 0,
                            message = { role = "assistant", content = raw },
                            finish_reason = "stop",
                        }},
                        usage = { prompt_tokens = 1, completion_tokens = 1, total_tokens = 2 },
                        echo = {
                            uri = ngx.var.request_uri,
                            method = ngx.req.get_method(),
                            authorization = hdrs["authorization"],
                        },
                    }))
                }
            }

            location / {
                content_by_lua_block {
                    ngx.status = 404
                    ngx.say('{"error":"unexpected path ' .. ngx.var.request_uri .. '"}')
                }
            }
        }

        # Upstream that is always rate limited, for the ai-proxy-multi fallback test.
        server {
            server_name always-429;
            listen 6753;
            default_type 'application/json';

            location / {
                content_by_lua_block {
                    ngx.status = 429
                    ngx.say('{"error":{"message":"rate limited","type":"rate_limit_error"}}')
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: provider module declares the Eden AI host, port and the four protocol paths
--- config
    location /t {
        content_by_lua_block {
            local provider = require("apisix.plugins.ai-providers.edenai")
            ngx.say("host=", provider.host, " port=", provider.port)
            for _, proto in ipairs({"openai-chat", "openai-responses",
                                    "openai-embeddings", "anthropic-messages"}) do
                local cap = provider.capabilities[proto]
                ngx.say(proto, " path=", cap.path,
                        " rewrite=", type(cap.rewrite_request_body))
            end
            ngx.say("bedrock-converse=", tostring(provider.capabilities["bedrock-converse"]))
        }
    }
--- response_body
host=api.edenai.run port=443
openai-chat path=/v3/chat/completions rewrite=function
openai-responses path=/v3/responses rewrite=function
openai-embeddings path=/v3/embeddings rewrite=nil
anthropic-messages path=/v3/v1/messages rewrite=function
bedrock-converse=nil



=== TEST 2: ai-proxy schema accepts provider edenai
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "edenai",
                auth = { header = { Authorization = "Bearer token" } },
                options = { model = "openai/gpt-latest" },
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



=== TEST 3: ai-proxy-multi schema accepts an edenai instance
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local ok, err = plugin.check_schema({
                instances = {{
                    name = "edenai",
                    provider = "edenai",
                    weight = 1,
                    auth = { header = { Authorization = "Bearer token" } },
                }},
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



=== TEST 4: ai-request-rewrite schema accepts edenai without override.endpoint
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "edenai",
                auth = { header = { Authorization = "Bearer token" } },
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



=== TEST 5: provider registry still lists every pre-existing provider plus edenai
--- config
    location /t {
        content_by_lua_block {
            local providers = require("apisix.plugins.ai-providers.schema").providers
            local expected = {
                "openai", "deepseek", "aimlapi", "anthropic",
                "openai-compatible", "azure-openai", "openrouter",
                "gemini", "vertex-ai", "bedrock", "edenai",
            }
            local set = {}
            for _, name in ipairs(providers) do
                set[name] = true
            end
            for _, name in ipairs(expected) do
                if not set[name] then
                    ngx.say("missing provider: ", name)
                    return
                end
            end
            ngx.say("count=", #providers)
        }
    }
--- response_body
count=11



=== TEST 6: ai-proxy schema rejects an unknown provider name
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "eden-ai",
                auth = { header = { Authorization = "Bearer token" } },
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "provider" validation failed: matches none of the enum values



=== TEST 7: ai-proxy schema rejects edenai without auth
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "edenai",
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "auth" is required



=== TEST 8: chat: default path, POST method, configured model and body reach the upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/gpt-latest" },
                            "override": { "endpoint": "http://127.0.0.1:6752" },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("status=", res.status, " uri=", body.echo.uri, " method=", body.echo.method)
            ngx.say("model=", sent.model, " messages=", #sent.messages,
                    " content=", sent.messages[1].content,
                    " stream_options=", tostring(sent.stream_options))
        }
    }
--- response_body
status=200 uri=/v3/chat/completions method=POST
model=openai/gpt-latest messages=1 content=hi stream_options=nil



=== TEST 9: chat: the configured Authorization header replaces the one sent by the client
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:6752" },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}]}',
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer client-supplied",
                },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            ngx.say("authorization=", body.echo.authorization)
        }
    }
--- response_body
authorization=Bearer token



=== TEST 10: chat: llm_options.max_tokens is written as max_tokens and nothing else
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": {
                                "endpoint": "http://127.0.0.1:6752",
                                "llm_options": { "max_tokens": 321 }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"model":"anthropic/claude-sonnet-latest","max_tokens":5,'
                    .. '"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", sent.max_tokens,
                    " max_completion_tokens=", tostring(sent.max_completion_tokens),
                    " max_output_tokens=", tostring(sent.max_output_tokens))
        }
    }
--- response_body
max_tokens=321 max_completion_tokens=nil max_output_tokens=nil



=== TEST 11: chat: caller parameters are forwarded untouched when nothing is configured
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:6752" },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"model":"mistral/mistral-large-latest","max_tokens":77,'
                    .. '"temperature":0.3,"user":"alice","fallbacks":["openai/gpt-latest"],'
                    .. '"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("model=", sent.model, " max_tokens=", sent.max_tokens,
                    " temperature=", sent.temperature, " user=", sent.user,
                    " fallbacks=", sent.fallbacks[1])
        }
    }
--- response_body
model=mistral/mistral-large-latest max_tokens=77 temperature=0.3 user=alice fallbacks=openai/gpt-latest



=== TEST 12: chat: streaming requests get stream_options.include_usage, as for every OpenAI-chat provider
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": { "endpoint": "http://127.0.0.1:6752" },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"stream":true,"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("stream=", tostring(sent.stream),
                    " include_usage=", tostring(sent.stream_options.include_usage))
        }
    }
--- response_body
stream=true include_usage=true



=== TEST 13: responses: default path, max_output_tokens mapping, no stream_options injection
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/responses",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/gpt-latest" },
                            "override": {
                                "endpoint": "http://127.0.0.1:6752",
                                "llm_options": { "max_tokens": 222 }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/v1/responses", {
                method = "POST",
                body = '{"input":"hi","stream":true,"instructions":"be brief"}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("status=", res.status, " uri=", body.echo.uri)
            ngx.say("model=", sent.model, " input=", sent.input,
                    " instructions=", sent.instructions,
                    " max_output_tokens=", sent.max_output_tokens,
                    " max_tokens=", tostring(sent.max_tokens),
                    " stream_options=", tostring(sent.stream_options))
        }
    }
--- response_body
status=200 uri=/v3/responses
model=openai/gpt-latest input=hi instructions=be brief max_output_tokens=222 max_tokens=nil stream_options=nil



=== TEST 14: embeddings: default path and untouched input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/embeddings",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/text-embedding-3-small" },
                            "override": {
                                "endpoint": "http://127.0.0.1:6752",
                                "llm_options": { "max_tokens": 9 }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/embeddings", {
                method = "POST",
                body = '{"input":["one","two"],"encoding_format":"float"}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("status=", res.status, " uri=", body.echo.uri)
            ngx.say("model=", sent.model, " input=", table.concat(sent.input, ","),
                    " encoding_format=", sent.encoding_format,
                    " max_tokens=", tostring(sent.max_tokens))
        }
    }
--- response_body
status=200 uri=/v3/embeddings
model=openai/text-embedding-3-small input=one,two encoding_format=float max_tokens=nil



=== TEST 15: anthropic messages: default path, native pass-through (no OpenAI conversion), max_tokens mapping
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "anthropic/claude-sonnet-latest" },
                            "override": {
                                "endpoint": "http://127.0.0.1:6752",
                                "llm_options": { "max_tokens": 333 }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages", {
                method = "POST",
                body = '{"max_tokens":10,"system":"You are terse",'
                    .. '"messages":[{"role":"user","content":[{"type":"text","text":"hi"}]}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("status=", res.status, " uri=", body.echo.uri)
            ngx.say("model=", sent.model, " system=", sent.system,
                    " messages=", #sent.messages, " role=", sent.messages[1].role,
                    " content_type=", sent.messages[1].content[1].type,
                    " max_tokens=", sent.max_tokens,
                    " stream_options=", tostring(sent.stream_options))
        }
    }
--- response_body
status=200 uri=/v3/v1/messages
model=anthropic/claude-sonnet-latest system=You are terse messages=1 role=user content_type=text max_tokens=333 stream_options=nil



=== TEST 16: override.endpoint with a path and query is used verbatim, the provider path is not prepended
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": {
                                "endpoint": "http://127.0.0.1:6752/v3/custom/completions?region=eu"
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            ngx.say("status=", res.status, " uri=", body.echo.uri)
        }
    }
--- response_body
status=200 uri=/v3/custom/completions?region=eu



=== TEST 17: set route to the fixture upstream for chat protocol tests
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
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/gpt-latest" },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
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



=== TEST 18: chat non-streaming response and usage are passed through and token vars are extracted
--- request
POST /anything
{"messages":[{"role":"system","content":"You are a mathematician"},{"role":"user","content":"What is 1+1?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/chat\/completions\" - openai\/gpt-latest [\d.]+ 23 8 31 false /



=== TEST 19: chat streaming: SSE frames, the usage chunk and the [DONE] terminator reach the client unchanged
--- request
POST /anything
{"stream":true,"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
X-AI-Fixture-Flush-Events: 1
--- error_code: 200
--- response_headers
Content-Type: text/event-stream
--- response_body_like eval
qr/^data: \{"id":"chatcmpl-abc123".*"delta":\{"role":"assistant","content":""\}.*\n\n(?s:.*)"usage":\{"prompt_tokens":10,"completion_tokens":8,"total_tokens":18\}\}\n\ndata: \[DONE\]\n\n$/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/chat\/completions\" - openai\/gpt-latest [\d.]+ 10 8 18 true /



=== TEST 20: chat streaming without a usage chunk still terminates cleanly and reports zero tokens
--- request
POST /anything
{"stream":true,"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-streaming-no-usage.sse
--- error_code: 200
--- response_body_like eval
qr/data: \[DONE\]\n\n$/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/chat\/completions\" - openai\/gpt-latest [\d.]+ 0 0 0 true /



=== TEST 21: a 4xx upstream error body and status are returned to the client as-is
--- request
POST /anything
{"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-error.json
X-AI-Fixture-Status: 422
--- error_code: 422
--- response_body_like eval
qr/"error"/



=== TEST 22: set route for native Anthropic Messages streaming through the fixture upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/messages"
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



=== TEST 23: anthropic messages non-streaming response is passed through with Anthropic usage mapped
--- request
POST /v1/messages
{"model":"anthropic/claude-sonnet-latest","max_tokens":64,"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- error_code: 200
--- response_body_like eval
qr/"type": "message"(?s:.*)"stop_reason": "end_turn"/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/messages\" anthropic\/claude-sonnet-latest anthropic\/claude-sonnet-latest [\d.]+ 10 8 18 false /



=== TEST 24: anthropic messages streaming keeps the native event names and ends with message_stop
--- request
POST /v1/messages
{"model":"anthropic/claude-sonnet-latest","max_tokens":64,"stream":true,"messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: anthropic/messages-streaming.sse
X-AI-Fixture-Flush-Events: 1
--- error_code: 200
--- response_headers
Content-Type: text/event-stream
--- response_body_like eval
qr/^event: message_start\n(?s:.*)event: content_block_delta\ndata: \{"type":"content_block_delta","index":0,"delta":\{"type":"text_delta","text":"Hello"\}\}\n\n(?s:.*)event: message_stop\ndata: \{"type":"message_stop"\}\n\n$/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/messages\" anthropic\/claude-sonnet-latest anthropic\/claude-sonnet-latest [\d.]+ 10 8 18 true /



=== TEST 25: set route for Responses API streaming through the fixture upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/responses",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/gpt-latest" },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/responses"
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



=== TEST 26: responses non-streaming response is passed through and usage is extracted
--- request
POST /v1/responses
{"input":"What is 1+1?"}
--- more_headers
X-AI-Fixture: openai/responses-basic.json
--- error_code: 200
--- response_body_like eval
qr/"object": "response"(?s:.*)"text": "1 \+ 1 = 2\."/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/responses\" - openai\/gpt-latest [\d.]+ 10 5 15 false /



=== TEST 27: responses streaming ends with response.completed and usage is read from it
--- request
POST /v1/responses
{"input":"Hello","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming.sse
X-AI-Fixture-Flush-Events: 1
--- error_code: 200
--- response_headers
Content-Type: text/event-stream
--- response_body_like eval
qr/^event: response\.output_text\.delta\n(?s:.*)event: response\.completed\ndata: \{"type":"response\.completed","response":\{"usage":\{"input_tokens":10,"output_tokens":5,"total_tokens":15\}\}\}\n\n$/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/responses\" - openai\/gpt-latest [\d.]+ 10 5 15 true /



=== TEST 28: set route for embeddings through the fixture upstream
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
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/text-embedding-3-small" },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/embeddings"
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



=== TEST 29: embeddings response is passed through and prompt tokens are extracted
--- request
POST /embeddings
{"input":"The quick brown fox"}
--- more_headers
X-AI-Fixture: openai/embeddings-list.json
--- error_code: 200
--- response_body_like eval
qr/"object": "embedding"/
--- access_log eval
qr/127\.0\.0\.1:1980 200 [\d.]+ \"http:\/\/\S+\/v1\/embeddings\" - openai\/text-embedding-3-small [\d.]+ 8 0 8 false /



=== TEST 30: ai-proxy-multi: an edenai instance resolves the default chat path and sends its own credentials
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "edenai-primary",
                                    "provider": "edenai",
                                    "weight": 1,
                                    "auth": { "header": { "Authorization": "Bearer multi-token" } },
                                    "options": { "model": "openai/gpt-latest" },
                                    "override": { "endpoint": "http://127.0.0.1:6752" }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local sent = cjson.decode(body.choices[1].message.content)
            ngx.say("status=", res.status, " uri=", body.echo.uri,
                    " authorization=", body.echo.authorization, " model=", sent.model)
        }
    }
--- response_body
status=200 uri=/v3/chat/completions authorization=Bearer multi-token model=openai/gpt-latest



=== TEST 31: ai-proxy-multi: a 429 from the preferred edenai instance falls back to the second one
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": ["http_429"],
                            "instances": [
                                {
                                    "name": "edenai-rate-limited",
                                    "provider": "edenai",
                                    "priority": 1,
                                    "weight": 1,
                                    "auth": { "header": { "Authorization": "Bearer token-a" } },
                                    "options": { "model": "openai/gpt-latest" },
                                    "override": { "endpoint": "http://127.0.0.1:6753" }
                                },
                                {
                                    "name": "edenai-fallback",
                                    "provider": "edenai",
                                    "priority": 0,
                                    "weight": 1,
                                    "auth": { "header": { "Authorization": "Bearer token" } },
                                    "options": { "model": "openai/gpt-latest" },
                                    "override": {
                                        "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 32: the request is served by the fallback instance after the 429
--- request
POST /anything
{"messages":[{"role":"user","content":"What is 1+1?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/
--- error_log
rate limited



=== TEST 33: ai-request-rewrite with edenai uses the default chat path and rewrites the client body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-request-rewrite": {
                            "prompt": "Translate to French",
                            "provider": "edenai",
                            "auth": { "header": { "Authorization": "Bearer token" } },
                            "options": { "model": "openai/gpt-latest" },
                            "override": { "endpoint": "http://127.0.0.1:6752" },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1980": 1 }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/echo", {
                method = "POST",
                body = "hello world",
                headers = { ["Content-Type"] = "text/plain" },
            }))
            -- /echo on the fixture upstream returns the body ai-request-rewrite
            -- forwarded, which the echo-edenai upstream set to the raw request it
            -- received from the plugin.
            local cjson = require("cjson.safe")
            local sent = cjson.decode(res.body)
            ngx.say("status=", res.status, " model=", sent.model,
                    " system=", sent.messages[1].content,
                    " user=", sent.messages[2].content,
                    " stream=", tostring(sent.stream))
        }
    }
--- response_body
status=200 model=openai/gpt-latest system=Translate to French user=hello world stream=false
