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

    my $http_config = $block->http_config // <<_EOC_;
        # Upstream that echoes the request body it receives so the test can
        # assert exactly what was forwarded by ai-proxy.
        server {
            server_name echo-openai;
            listen 6732;
            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data() or ""
                    ngx.status = 200
                    ngx.say(json.encode({
                        id = "chatcmpl-1",
                        object = "chat.completion",
                        model = "echo",
                        choices = {{
                            index = 0,
                            message = { role = "assistant", content = raw },
                            finish_reason = "stop",
                        }},
                        usage = { prompt_tokens = 1, completion_tokens = 1, total_tokens = 2 },
                    }))
                }
            }

            location /v1/responses {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data() or ""
                    ngx.status = 200
                    ngx.say(json.encode({
                        id = "resp_1",
                        object = "response",
                        created_at = 1,
                        model = "echo",
                        output = {{
                            type = "message",
                            role = "assistant",
                            content = {{ type = "output_text", text = raw }},
                        }},
                        usage = { input_tokens = 1, output_tokens = 1, total_tokens = 2 },
                    }))
                }
            }

            location /v1/messages {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data() or ""
                    ngx.status = 200
                    ngx.say(json.encode({
                        id = "msg_1",
                        type = "message",
                        role = "assistant",
                        model = "echo",
                        content = {{ type = "text", text = raw }},
                        stop_reason = "end_turn",
                        usage = { input_tokens = 1, output_tokens = 1 },
                    }))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: schema rejects unknown fields in llm_options
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
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "temperature": 0.5
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like: .*additional properties forbidden.*



=== TEST 2: schema rejects unknown target protocol key in request_body
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
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "not-a-protocol": { "x": 1 }
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like: .*additional properties forbidden.*



=== TEST 3: llm_options: openai provider maps max_tokens to max_completion_tokens
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "max_tokens": 555
                                }
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_completion_tokens=", echoed.max_completion_tokens)
        }
    }
--- response_body
max_completion_tokens=555



=== TEST 4: llm_options: openai-compatible provider maps max_tokens to max_tokens
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
                            "provider": "openai-compatible",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "max_tokens": 444
                                }
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=444



=== TEST 5: llm_options: openai responses API maps max_tokens to max_output_tokens
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "max_tokens": 333
                                }
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
                body = '{"model":"gpt-4o","input":"hello"}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.output[1].content[1].text)
            ngx.say("max_output_tokens=", echoed.max_output_tokens)
        }
    }
--- response_body
max_output_tokens=333



=== TEST 6: llm_options: ai-proxy-multi per-instance override
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
                            "instances": [{
                                "name": "test",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer t" } },
                                "override": {
                                    "endpoint": "http://localhost:6732",
                                    "llm_options": {
                                        "max_tokens": 222
                                    }
                                }
                            }],
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_completion_tokens=", echoed.max_completion_tokens)
        }
    }
--- response_body
max_completion_tokens=222



=== TEST 7: llm_options always force-overwrites client value
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
                            "provider": "openai-compatible",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "max_tokens": 555
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            -- Client sends max_tokens=999, llm_options should force-overwrite it
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- llm_options always force-overwrites: 555 wins over 999
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=555



=== TEST 8: request_body: openai-chat override writes fields on outgoing body
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": {
                                        "max_tokens": 555,
                                        "temperature": 0.1
                                    }
                                },
                                "request_body_force_override": true
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", echoed.max_tokens,
                    " temperature=", echoed.temperature)
        }
    }
--- response_body
max_tokens=555 temperature=0.1



=== TEST 9: request_body: non-force deep merge fills missing nested keys without overwriting existing
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": {
                                        "stream_options": { "extra": 1 }
                                    }
                                }
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
                body = '{"messages":[{"role":"user","content":"hi"}],"stream":true}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- Non-force mode: stream_options.include_usage was set by
            -- prepare_outgoing_request; extra=1 should be filled in without
            -- disturbing include_usage.
            ngx.say("include_usage=", tostring(echoed.stream_options.include_usage),
                    " extra=", tostring(echoed.stream_options.extra))
        }
    }
--- response_body
include_usage=true extra=1



=== TEST 10: request_body: array values are replaced wholesale (stop sequences)
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": {
                                        "stop": ["a", "b"]
                                    }
                                },
                                "request_body_force_override": true
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
                body = '{"messages":[{"role":"user","content":"hi"}],"stop":["x"]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("stop=", cjson.encode(echoed.stop))
        }
    }
--- response_body
stop=["a","b"]



=== TEST 11: request_body: override keyed by non-matching target protocol is ignored
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "anthropic-messages": { "max_tokens": 999 }
                                }
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", tostring(echoed.max_tokens))
        }
    }
--- response_body
max_tokens=nil



=== TEST 12: request_body: default mode - client value takes priority
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
                            "provider": "openai-compatible",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": { "max_tokens": 555 }
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            -- Client sends max_tokens=999 which should NOT be overwritten
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- max_tokens from client (999) wins in default mode
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=999



=== TEST 13: request_body: force_override mode - override overwrites client fields
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
                            "provider": "openai-compatible",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body_force_override": true,
                                "request_body": {
                                    "openai-chat": { "max_tokens": 555 }
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            -- Client sends max_tokens=999 which SHOULD be overwritten
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- max_tokens from override (555) wins
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=555



=== TEST 14: request_body: override applies to target protocol after converter
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
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": { "max_tokens": 77 },
                                    "anthropic-messages": { "max_tokens": 999 }
                                },
                                "request_body_force_override": true
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
                body = '{"model":"claude-3","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            ngx.status = res.status
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.content[1].text)
            ngx.say("max_tokens=", echoed.max_tokens,
                    " has_messages=", tostring(type(echoed.messages) == "table"))
        }
    }
--- response_body
max_tokens=77 has_messages=true



=== TEST 15: ai-proxy-multi per-instance request_body override
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
                            "instances": [{
                                "name": "only",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer t" } },
                                "override": {
                                    "endpoint": "http://localhost:6732",
                                    "request_body": {
                                        "openai-chat": { "max_tokens": 321 }
                                    },
                                    "request_body_force_override": true
                                }
                            }],
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
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=321



=== TEST 16: both llm_options and request_body coexist, request_body wins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- llm_options sets max_tokens=100 (mapped to max_completion_tokens for openai)
            -- request_body sets max_tokens=200 for openai-chat (deep merge, applied after)
            -- request_body should win since it runs after llm_options
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "llm_options": {
                                    "max_tokens": 100
                                },
                                "request_body": {
                                    "openai-chat": {
                                        "max_completion_tokens": 200,
                                        "temperature": 0.5
                                    }
                                },
                                "request_body_force_override": true
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
            local echoed = cjson.decode(body.choices[1].message.content)
            -- request_body overwrites llm_options' max_completion_tokens
            ngx.say("max_completion_tokens=", echoed.max_completion_tokens,
                    " temperature=", echoed.temperature)
        }
    }
--- response_body
max_completion_tokens=200 temperature=0.5



=== TEST 17: effective_request_for_cache returns post-override body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- ai-proxy applies overrides; serverless-post-function (priority -2000)
            -- runs after ai-proxy access (priority 1040) in the access phase, invokes
            -- the helper, and logs its output. The test asserts BOTH the
            -- upstream-received body AND the helper output reflect the same
            -- post-override view.
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "options": { "model": "options-model" },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": { "temperature": 0.42 }
                                }
                            },
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "functions": ["return function(_, ctx)
                                local b = require('apisix.plugins.ai-proxy.base')
                                local cjson = require('cjson.safe')
                                local body, err = b.effective_request_for_cache(ctx)
                                ngx.log(ngx.WARN, 'EFFECTIVE_BODY=',
                                    body and cjson.encode(body)
                                          or ('ERR:' .. tostring(err)))
                            end"]
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"model":"client-model"}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("upstream model=", echoed.model,
                    " upstream temperature=", echoed.temperature)
        }
    }
--- response_body
upstream model=options-model upstream temperature=0.42
--- error_log eval
[
    qr/EFFECTIVE_BODY=.*"model":"options-model"/,
    qr/EFFECTIVE_BODY=.*"temperature":0\.42/,
]



=== TEST 18: effective_request_for_cache applies the converter (anthropic-messages -> openai-chat)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Client sends anthropic-messages format to an openai provider, which
            -- speaks openai-chat natively. The converter translates the body and
            -- override.request_body.openai-chat then applies. The helper should
            -- mirror this: convert first, then apply overrides. Distinctive
            -- post-converter marker: max_tokens (anthropic) becomes
            -- max_completion_tokens (openai-chat) and the original max_tokens
            -- is stripped by the converter ("never forward max_tokens").
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "openai-chat": { "temperature": 0.42 }
                                }
                            },
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "functions": ["return function(_, ctx)
                                local b = require('apisix.plugins.ai-proxy.base')
                                local cjson = require('cjson.safe')
                                local body, err = b.effective_request_for_cache(ctx)
                                ngx.log(ngx.WARN, 'EFFECTIVE_BODY=',
                                    body and cjson.encode(body)
                                          or ('ERR:' .. tostring(err)))
                            end"]
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages", {
                method = "POST",
                body = '{"model":"claude-3","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            ngx.status = res.status
            ngx.say("status=", res.status)
        }
    }
--- response_body
status=200
--- error_log eval
[
    qr/EFFECTIVE_BODY=.*"max_completion_tokens":10/,
    qr/EFFECTIVE_BODY=.*"temperature":0\.42/,
]
--- no_error_log eval
qr/EFFECTIVE_BODY=.*"max_tokens":10/
