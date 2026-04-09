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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name anthropic;
            listen 16725;

            default_type 'application/json';

            location /v1/messages {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local ngx = ngx

                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()
                    body = json.decode(body)

                    if not body or not body.messages then
                        ngx.status = 400
                        ngx.say('{"type":"error","error":{"type":"invalid_request_error","message":"missing messages"}}')
                        return
                    end

                    local api_key = ngx.req.get_headers()["x-api-key"]
                    if api_key ~= "test-key" then
                        ngx.status = 401
                        ngx.say('{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}')
                        return
                    end

                    if body.stream then
                        ngx.header["Content-Type"] = "text/event-stream"

                        -- message_start with input_tokens and cache tokens
                        local message_start = json.encode({
                            type = "message_start",
                            message = {
                                id = "msg_test123",
                                type = "message",
                                role = "assistant",
                                model = body.model or "claude-sonnet-4-20250514",
                                content = {},
                                usage = {
                                    input_tokens = 50,
                                    output_tokens = 0,
                                    cache_creation_input_tokens = 100,
                                    cache_read_input_tokens = 200,
                                },
                            },
                        })
                        ngx.say("event: message_start")
                        ngx.say("data: " .. message_start)
                        ngx.say("")

                        -- content_block_start
                        ngx.say("event: content_block_start")
                        ngx.say('data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}')
                        ngx.say("")

                        -- content_block_delta
                        ngx.say("event: content_block_delta")
                        ngx.say('data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello from Claude!"}}')
                        ngx.say("")

                        -- content_block_stop
                        ngx.say("event: content_block_stop")
                        ngx.say('data: {"type":"content_block_stop","index":0}')
                        ngx.say("")

                        -- message_delta with output_tokens
                        local message_delta = json.encode({
                            type = "message_delta",
                            delta = { stop_reason = "end_turn" },
                            usage = {
                                output_tokens = 30,
                            },
                        })
                        ngx.say("event: message_delta")
                        ngx.say("data: " .. message_delta)
                        ngx.say("")

                        -- message_stop
                        ngx.say("event: message_stop")
                        ngx.say("data: {}")
                        ngx.say("")
                    else
                        ngx.status = 200
                        ngx.say(json.encode({
                            id = "msg_test456",
                            type = "message",
                            role = "assistant",
                            model = body.model or "claude-sonnet-4-20250514",
                            content = {{
                                type = "text",
                                text = "Hello from Claude!",
                            }},
                            stop_reason = "end_turn",
                            usage = {
                                input_tokens = 50,
                                output_tokens = 30,
                                cache_creation_input_tokens = 100,
                                cache_read_input_tokens = 200,
                            },
                        }))
                    end
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: schema validation - expression strategy requires cost_expr
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rate-limiting")
            local configs = {
                -- expression without cost_expr
                {
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                },
                -- expression with empty cost_expr
                {
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                    cost_expr = "",
                },
                -- expression with invalid cost_expr syntax
                {
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                    cost_expr = "invalid $$$ syntax %%%",
                },
                -- valid expression
                {
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                    cost_expr = "input_tokens + output_tokens",
                },
                -- valid complex expression
                {
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                    cost_expr = "(input_tokens - cache_read_input_tokens) + cache_creation_input_tokens * 1.25 + output_tokens",
                },
            }
            for i, conf in ipairs(configs) do
                local ok, err = plugin.check_schema(conf)
                if ok then
                    ngx.say("config " .. i .. ": valid")
                else
                    ngx.say("config " .. i .. ": invalid")
                end
            end
        }
    }
--- response_body
config 1: invalid
config 2: invalid
config 3: invalid
config 4: valid
config 5: valid



=== TEST 2: set route with expression rate limiting (non-streaming, native Anthropic)
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
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key",
                                    "anthropic-version": "2023-06-01"
                                }
                            },
                            "options": {
                                "model": "claude-sonnet-4-20250514"
                            },
                            "override": {
                                "endpoint": "http://localhost:16725"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens + cache_creation_input_tokens + output_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 3: non-streaming request - expression counts input_tokens + cache_creation + output_tokens
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 499",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 319",
]
--- no_error_log
[error]



=== TEST 4: set route with expression rate limiting (streaming, native Anthropic)
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
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key",
                                    "anthropic-version": "2023-06-01"
                                }
                            },
                            "options": {
                                "model": "claude-sonnet-4-20250514"
                            },
                            "override": {
                                "endpoint": "http://localhost:16725"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens + cache_creation_input_tokens + output_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 5: streaming request - verify token usage accumulation and rate limiting
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"stream":true,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"stream":true,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 499",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 319",
]
--- no_error_log
[error]



=== TEST 6: set route with cache-aware ITPM expression (excludes cache_read_input_tokens)
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
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key",
                                    "anthropic-version": "2023-06-01"
                                }
                            },
                            "options": {
                                "model": "claude-sonnet-4-20250514"
                            },
                            "override": {
                                "endpoint": "http://localhost:16725"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 100,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens + cache_creation_input_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 7: cache-aware ITPM - cost=150 exceeds limit=100 after first request, second rejected
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- error_code eval
[200, 503]
--- no_error_log
[error]



=== TEST 8: set route with weighted expression (cache_read costs 10%, cache_creation costs 125%)
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
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key",
                                    "anthropic-version": "2023-06-01"
                                }
                            },
                            "options": {
                                "model": "claude-sonnet-4-20250514"
                            },
                            "override": {
                                "endpoint": "http://localhost:16725"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 1000,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens + cache_read_input_tokens * 0.1 + cache_creation_input_tokens * 1.25 + output_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 9: weighted expression - two requests (cost = 50 + 200*0.1 + 100*1.25 + 30 = 225 each)
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 999",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 774",
]
--- no_error_log
[error]



=== TEST 10: expression with missing variables defaults to 0
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
                            "provider": "anthropic",
                            "auth": {
                                "header": {
                                    "x-api-key": "test-key",
                                    "anthropic-version": "2023-06-01"
                                }
                            },
                            "options": {
                                "model": "claude-sonnet-4-20250514"
                            },
                            "override": {
                                "endpoint": "http://localhost:16725"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens + nonexistent_field + output_tokens"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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



=== TEST 11: missing variable defaults to 0 - cost = 50 + 0 + 30 = 80 per request
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 499",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 419",
]
--- no_error_log
[error]
