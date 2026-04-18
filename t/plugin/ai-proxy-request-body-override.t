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

=== TEST 1: schema rejects unknown target protocol key
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



=== TEST 2: openai-chat override writes max_tokens on outgoing body
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
            ngx.say("max_tokens=", echoed.max_tokens,
                    " temperature=", echoed.temperature)
        }
    }
--- response_body
max_tokens=555 temperature=0.1



=== TEST 3: deep object merge preserves sibling keys (stream_options)
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
            -- Upstream returns JSON but we injected stream=true so the
            -- provider adapter sets include_usage=true on stream_options.
            -- Our override adds extra=1. Deep merge must keep both.
            -- The echo server returns non-SSE which means ai-proxy treats
            -- it as a normal response; the body.choices[1].message.content
            -- contains the raw outgoing body as JSON string.
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("include_usage=", tostring(echoed.stream_options.include_usage),
                    " extra=", tostring(echoed.stream_options.extra))
        }
    }
--- response_body
include_usage=true extra=1



=== TEST 4: array values are replaced wholesale (stop sequences, force mode)
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
                                "request_body_force_override": true,
                                "request_body": {
                                    "openai-chat": {
                                        "stop": ["a", "b"]
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



=== TEST 5: override keyed by non-matching target protocol is ignored
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



=== TEST 6: ai-proxy-multi per-instance override
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
            ngx.say("max_tokens=", echoed.max_tokens)
        }
    }
--- response_body
max_tokens=321



=== TEST 7: force override applies to target protocol after converter (anthropic -> openai-chat)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- openai provider only natively supports openai-chat; an
            -- anthropic-messages client request is converted to openai-chat
            -- before being sent upstream. Therefore the override keyed by
            -- "openai-chat" must apply; the one keyed by
            -- "anthropic-messages" must not.
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
                                    "openai-chat": { "max_tokens": 77 },
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
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/v1/messages", {
                method = "POST",
                body = '{"model":"claude-3","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            ngx.status = res.status
            local cjson = require("cjson.safe")
            -- Client receives response in anthropic format (converter back).
            local body = cjson.decode(res.body)
            -- content[1].text contains the echoed outgoing body (openai-chat form)
            local echoed = cjson.decode(body.content[1].text)
            ngx.say("max_tokens=", echoed.max_tokens,
                    " has_messages=", tostring(type(echoed.messages) == "table"))
        }
    }
--- response_body
max_tokens=77 has_messages=true



=== TEST 8: default mode - client request params take priority over override
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
            -- max_tokens from client (999) wins; temperature from override (0.1) fills in
            ngx.say("max_tokens=", echoed.max_tokens,
                    " temperature=", echoed.temperature)
        }
    }
--- response_body
max_tokens=999 temperature=0.1



=== TEST 9: force_override mode - override forcefully overwrites client params
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
                                "request_body_force_override": true,
                                "request_body": {
                                    "openai-chat": {
                                        "max_tokens": 555,
                                        "temperature": 0.1
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
            ngx.say("max_tokens=", echoed.max_tokens,
                    " temperature=", echoed.temperature)
        }
    }
--- response_body
max_tokens=555 temperature=0.1



=== TEST 10: default mode fills missing fields without touching existing ones
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
                                "request_body_force_override": false,
                                "request_body": {
                                    "openai-chat": {
                                        "max_tokens": 555,
                                        "temperature": 0.1,
                                        "top_p": 0.9
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
            -- Client sends only max_tokens; temperature and top_p should come from override
            local res = assert(http:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/chat", {
                method = "POST",
                body = '{"messages":[{"role":"user","content":"hi"}],"max_tokens":999}',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local cjson = require("cjson.safe")
            local body = cjson.decode(res.body)
            local echoed = cjson.decode(body.choices[1].message.content)
            ngx.say("max_tokens=", echoed.max_tokens,
                    " temperature=", echoed.temperature,
                    " top_p=", echoed.top_p)
        }
    }
--- response_body
max_tokens=999 temperature=0.1 top_p=0.9
