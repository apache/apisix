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

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    if (!defined $block->http_config) {
        $block->set_value("http_config", <<_EOC_);
server {
    listen 1990;
    default_type 'application/json';

    location /v1/embeddings {
        content_by_lua_block {
            local fixture_loader = require("lib.fixture_loader")
            local content, err = fixture_loader.load("openai/embeddings-list.json")
            if not content then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = 200
            ngx.print(content)
        }
    }
}
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: valid config - exact layer only
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "exact" },
                exact = { ttl = 600 },
                redis_host = "127.0.0.1",
                redis_port = 6379,
            })

            if not ok then
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: valid config - both layers with semantic embedding
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "exact", "semantic" },
                exact = { ttl = 3600 },
                semantic = {
                    similarity_threshold = 0.95,
                    ttl = 86400,
                    embedding = {
                        provider = "openai",
                        endpoint = "https://api.openai.com/v1/embeddings",
                        api_key = "sk-test",
                    },
                },
                redis_host = "127.0.0.1",
                redis_port = 6379,
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



=== TEST 3: semantic without embedding config - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
                redis_host = "127.0.0.1",
            })
            
            if not ok then
                ngx.say("failed: ", err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed: semantic layer requires semantic.embedding to be configured



=== TEST 4: invalid layer value - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "invalid_layer" },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/.*property "layers" validation failed:.*matches none of the enum values.*/



=== TEST 5: unsupported embedding provider - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
                semantic = {
                    embedding = {
                        provider = "some-unknown-provider",
                        endpoint = "https://example.com/embeddings",
                        api_key = "key",
                    },
                },
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



=== TEST 6: similarity_threshold out of range - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
                semantic = {
                    similarity_threshold = 1.5,
                    embedding = {
                        provider = "openai",
                        endpoint = "https://api.openai.com/v1/embeddings",
                        api_key = "sk-test",
                    },
                },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/.*property "similarity_threshold" validation failed: expected 1\.5 to be at most.*/



=== TEST 7: layers empty array - should fail (minItems=1)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = {},
                redis_host = "127.0.0.1",
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/.*property "layers" validation failed: expect array to have at least 1 items.*/



=== TEST 8: set up route for L1 cache tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/exact",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact"],
                            "exact": { "ttl": 60 },
                            "redis_host": "127.0.0.1",
                            "bypass_on": [{"header": "X-Cache-Bypass", "equals": "1"}]
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



=== TEST 9: first request - cache MISS, upstream called
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the answer to life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 10: second identical request - cache HIT-L1, no upstream call
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the answer to life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- response_headers_like
X-AI-Cache-Age: \d+
--- response_body_like eval
qr/"content":\s?"1 \+ 1 = 2\."/
--- error_log
ai-cache: L1 hit for key



=== TEST 11: bypass header - BYPASS, upstream called, not cached
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the bypass question?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-Cache-Bypass: 1
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 12: same prompt without bypass after bypass - still MISS (bypass did not cache)
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the bypass question?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 13: set up route with two bypass rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/exact",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact"],
                            "exact": { "ttl": 60 },
                            "redis_host": "127.0.0.1",
                            "bypass_on": [
                                {"header": "X-Cache-Bypass", "equals": "1"},
                                {"header": "X-Debug",        "equals": "true"}
                            ]
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



=== TEST 14: first bypass rule matches - BYPASS
--- request
POST /exact
{"messages":[{"role":"user","content":"multi-rule bypass test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-Cache-Bypass: 1
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 15: second bypass rule matches - BYPASS
--- request
POST /exact
{"messages":[{"role":"user","content":"multi-rule bypass test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-Debug: true
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 16: set up route for upstream-status filter tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/error",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact"],
                            "exact": { "ttl": 60 },
                            "redis_host": "127.0.0.1"
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



=== TEST 17: non-2xx upstream response - not cached (status code filter)
--- request
POST /error
{"messages":[{"role":"user","content":"trigger a server error"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 500
--- error_code: 500
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 18: same prompt after non-2xx - still MISS (was not cached)
--- request
POST /error
{"messages":[{"role":"user","content":"trigger a server error"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 500
--- error_code: 500
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 19: set up route with very small max_cache_body_size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/tiny",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact"],
                            "exact": { "ttl": 60 },
                            "max_cache_body_size": 5,
                            "redis_host": "127.0.0.1"
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



=== TEST 20: oversize response - MISS, log warns and skips cache write
--- request
POST /tiny
{"messages":[{"role":"user","content":"oversize body test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/
--- error_log
exceeds max_cache_body_size



=== TEST 21: same prompt after oversize - still MISS (was not cached)
--- request
POST /tiny
{"messages":[{"role":"user","content":"oversize body test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/
--- error_log
exceeds max_cache_body_size



=== TEST 22: set up route with custom cache header names
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/custom-headers",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact"],
                            "exact": { "ttl": 60 },
                            "headers": {
                                "cache_status": "X-Custom-Status",
                                "cache_age":    "X-Custom-Age"
                            },
                            "redis_host": "127.0.0.1"
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



=== TEST 23: MISS populates the cache and emits custom status header
--- request
POST /custom-headers
{"messages":[{"role":"user","content":"custom header test"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-Custom-Status: MISS
--- response_body_like eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/
--- wait: 1



=== TEST 24: HIT emits custom status and age headers (defaults not used)
--- request
POST /custom-headers
{"messages":[{"role":"user","content":"custom header test"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Custom-Status: HIT-L1
X-AI-Cache-Status:
X-AI-Cache-Age:
--- response_headers_like
X-Custom-Age: \d+
--- response_body_like eval
qr/"content":\s?"1 \+ 1 = 2\."/



=== TEST 25: clean up Redis cache state before semantic tests
--- config
    location /t {
        content_by_lua_block {
            local redis = require("resty.redis")
            local red = redis:new()
            red:set_timeout(1000)
            assert(red:connect("127.0.0.1", 6379))

            red["FT.DROPINDEX"](red, "ai-cache-idx-3", "DD")

            local keys = red:keys("ai-cache:*")
            if type(keys) == "table" and #keys > 0 then
                red:del(unpack(keys))
            end

            red:close()
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 26: set up route for L2 semantic cache tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/5',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980/v1/chat/completions"
                            }
                        },
                        "ai-cache": {
                            "layers": ["exact", "semantic"],
                            "exact": {
                                "ttl": 60
                            },
                            "semantic": {
                                "similarity_threshold": 0.90,
                                "ttl": 300,
                                "embedding": {
                                    "provider": "openai",
                                    "endpoint": "http://127.0.0.1:1990/v1/embeddings",
                                    "api_key": "test-key"
                                }
                            },
                            "redis_host": "127.0.0.1"
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



=== TEST 27: L2 - first request, cache MISS, stored in L2
--- request
POST /semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 28: L2 - different wording hits L2 (same vector from fixture)
--- request
POST /semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L2
--- response_headers_like
X-AI-Cache-Similarity: \d+(\.\d+)?
--- response_body_like eval
qr/"content":\s?"1 \+ 1 = 2\."/
--- error_log
ai-cache: L2 hit



=== TEST 29: L2 - paraphrase now hits L1 (backfilled by the previous L2 hit)
--- request
POST /semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- response_body_like eval
qr/"content":\s?"1 \+ 1 = 2\."/
--- error_log
ai-cache: L1 hit for key



=== TEST 30: streaming MISS - upstream called, response cached via log phase
--- request
POST /exact
{"messages":[{"role":"user","content":"Stream me something cool"}],"stream":true}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-streaming.sse
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/data:.*"content":"Hello"/



=== TEST 31: streaming HIT - Content-Type is text/event-stream, SSE body returned
--- request
POST /exact
{"messages":[{"role":"user","content":"Stream me something cool"}],"stream":true}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
Content-Type: text/event-stream
--- response_body_like eval
qr/data:.*"content":\s?"Hello!"/
--- wait: 1



=== TEST 32: non-streaming HIT after streaming MISS - returns JSON
--- request
POST /exact
{"messages":[{"role":"user","content":"Stream me something cool"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
Content-Type: application/json
--- response_body_like eval
qr/"content":\s?"Hello!"/
