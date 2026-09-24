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
                                "endpoint": "http://127.0.0.1:1980"
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
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 320",
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
                                "endpoint": "http://127.0.0.1:1980"
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
--- more_headers
X-AI-Fixture: anthropic/messages-streaming-with-cache.sse
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"stream":true,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"stream":true,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 320",
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
                                "endpoint": "http://127.0.0.1:1980"
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
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
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
                                "endpoint": "http://127.0.0.1:1980"
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
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 1000",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 775",
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
                                "endpoint": "http://127.0.0.1:1980"
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
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 420",
]
--- no_error_log
[error]



=== TEST 12: set route with expression that can yield negative cost
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
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 100,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens - cache_read_input_tokens"
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



=== TEST 13: negative expression result clamped to 0 - cost = 50 - 200 = -150, clamped to 0
--- more_headers
X-AI-Fixture: anthropic/messages-with-cache.json
--- pipelined_requests eval
[
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/messages\n" . '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}',
]
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 100",
    "X-AI-RateLimit-Remaining-ai-proxy-anthropic: 100",
]
--- no_error_log
[error]



=== TEST 14: set route with expression reading nested usage leaves (OpenAI Responses)
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens - cached_tokens + output_tokens + reasoning_tokens"
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



=== TEST 15: nested leaves - cost = 40 - 12 + 20 + 8 = 56 per request
--- pipelined_requests eval
[
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
]
--- more_headers
X-AI-Fixture: openai/responses-with-cache.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 444",
]
--- no_error_log
[error]



=== TEST 16: nested leaves, streaming - cost = 20 - 10 + 5 + 3 = 18 per request
--- pipelined_requests eval
[
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":true,"input":"Hello"}',
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":true,"input":"Hello"}',
]
--- more_headers
X-AI-Fixture: openai/responses-streaming-with-cache.sse
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 482",
]
--- no_error_log
[error]



=== TEST 17: set route with expression reading a leaf name present at two depths
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "cached_tokens"
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



=== TEST 18: top-level field wins over nested one - cost = 5 per request
--- pipelined_requests eval
[
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
]
--- more_headers
X-AI-Fixture: openai/responses-usage-clash.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 495",
]
--- no_error_log
[error]



=== TEST 19: set route with an explicit path to a field that also exists at the top level
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
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "input_tokens_details.cached_tokens"
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



=== TEST 20: explicit path reads the nested field - cost = 12 per request
--- pipelined_requests eval
[
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
    "POST /v1/responses\n" . '{"model":"gpt-4o-mini","stream":false,"input":"Hello"}',
]
--- more_headers
X-AI-Fixture: openai/responses-usage-clash.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 488",
]
--- no_error_log
[error]



=== TEST 21: set route with a bare name present in two sibling objects
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/chat/completions",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "audio_tokens"
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



=== TEST 22: ambiguous bare name charges the larger value - cost = 70 per request
--- pipelined_requests eval
[
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-usage-audio.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 430",
]
--- no_error_log
[alert]



=== TEST 23: ambiguous bare name logs the explicit paths to use
--- request
POST /v1/chat/completions
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-usage-audio.json
--- error_log
ambiguous usage field 'audio_tokens' in cost_expr matches completion_tokens_details.audio_tokens, prompt_tokens_details.audio_tokens, charging the larger value, use an explicit path instead



=== TEST 24: set route mixing explicit paths and bare names
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/chat/completions",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "prompt_tokens_details.audio_tokens * 2 + completion_tokens_details.audio_tokens + cached_tokens"
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



=== TEST 25: explicit paths resolve the clash - cost = 30 * 2 + 70 + 20 = 150 per request
--- pipelined_requests eval
[
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-usage-audio.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 350",
]
--- no_error_log
[error]



=== TEST 26: set route with explicit paths that do not exist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/chat/completions",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "prompt_tokens + no_such_details.audio_tokens + prompt_tokens_details.no_such_field"
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



=== TEST 27: missing explicit paths default to 0 - cost = 100 per request
--- pipelined_requests eval
[
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-usage-audio.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 400",
]
--- no_error_log
[error]



=== TEST 28: set route reading a field nested two levels deep
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/chat/completions",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "text_tokens + prompt_tokens_details.cached_tokens_details.text_tokens"
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



=== TEST 29: deep bare name and deep path both resolve, arrays are skipped - cost = 9 + 9 = 18 per request
--- pipelined_requests eval
[
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-usage-deep.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 482",
]
--- no_error_log
[error]



=== TEST 30: set route using math helpers and number literals around explicit paths
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/chat/completions",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o-mini"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 500,
                            "time_window": 60,
                            "limit_strategy": "expression",
                            "cost_expr": "floor(completion_tokens_details.audio_tokens / 1e1) + math.max(reasoning_tokens, 1)"
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



=== TEST 31: helpers and literals are left as is - cost = 7 + 10 = 17 per request
--- pipelined_requests eval
[
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
    "POST /v1/chat/completions\n" . '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-usage-audio.json
--- response_headers_like eval
[
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 500",
    "X-AI-RateLimit-Remaining-ai-proxy-openai: 483",
]
--- no_error_log
[error]



=== TEST 32: schema validation - malformed explicit paths are rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rate-limiting")
            local exprs = {
                "input_tokens_details..cached_tokens",
                "input_tokens_details. + 1",
                "math.floor(input_tokens_details.cached_tokens) + 1e3",
            }
            for i, expr in ipairs(exprs) do
                local ok, err = plugin.check_schema({
                    limit = 100,
                    time_window = 60,
                    limit_strategy = "expression",
                    cost_expr = expr,
                })
                ngx.say("expr ", i, ": ", ok and "valid" or err)
            end
        }
    }
--- response_body
expr 1: invalid cost_expr: invalid field reference: input_tokens_details..cached_tokens
expr 2: invalid cost_expr: invalid field reference: input_tokens_details.
expr 3: valid
