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

=== TEST 1: schema rejects unknown fields in request_body
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



=== TEST 2: openai provider maps max_tokens to max_completion_tokens
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



=== TEST 3: openai-compatible provider maps max_tokens to max_tokens
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



=== TEST 4: openai responses API maps max_tokens to max_output_tokens
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
                                "request_body": {
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



=== TEST 5: ai-proxy-multi per-instance override
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
                                    "request_body": {
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



=== TEST 6: cross-protocol: anthropic client to openai provider, override applies to target protocol
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
                                "request_body_force_override": true,
                                "request_body": {
                                    "max_tokens": 77
                                }
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
            -- openai provider maps to max_completion_tokens
            ngx.say("max_completion_tokens=", echoed.max_completion_tokens,
                    " has_messages=", tostring(type(echoed.messages) == "table"))
        }
    }
--- response_body
max_completion_tokens=77 has_messages=true



=== TEST 7: default mode - client value takes priority
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
            -- Client sends max_tokens=999 which should NOT be overwritten
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- max_tokens from client (999) wins
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=999



=== TEST 8: force_override mode - override forcefully overwrites client params
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
            -- Client sends max_tokens=999 which SHOULD be overwritten
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            -- max_tokens from override (555) wins over client (999)
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=555



=== TEST 9: default mode fills missing field
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
            -- Client does NOT send max_tokens; override should fill it in
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
max_tokens=555



=== TEST 10: openai chat - deprecated max_tokens in body is respected in default mode and cleared in force mode
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Route with default mode (no force)
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "model": { "name": "gpt-4" },
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "max_tokens": 999
                                }
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            local http = require("resty.http").new()
            local cjson = require("cjson.safe")

            -- Client sends deprecated max_tokens=200; default mode should NOT override
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":200}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("default: max_tokens=", echoed.max_tokens,
                    " max_completion_tokens=", echoed.max_completion_tokens)

            -- Switch to force mode
            code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/chat",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "model": { "name": "gpt-4" },
                            "auth": { "header": { "Authorization": "Bearer t" } },
                            "override": {
                                "endpoint": "http://localhost:6732",
                                "request_body": {
                                    "max_tokens": 999
                                },
                                "request_body_force_override": true
                            },
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code; return end

            ngx.sleep(0.5)

            -- Client sends deprecated max_tokens=200; force mode should clear it and set max_completion_tokens
            res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":200}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            body = cjson.decode(res.body)
            echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("force: max_tokens=", echoed.max_tokens,
                    " max_completion_tokens=", echoed.max_completion_tokens)
        }
    }
--- response_body
default: max_tokens=200 max_completion_tokens=nil
force: max_tokens=nil max_completion_tokens=999
