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
  - ai-cache
_EOC_
    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $user_yaml_config);
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 6731;
        default_type 'application/json';
        location / {
            content_by_lua_block {
                ngx.status = 500
                ngx.say([[{"error":{"message":"primary down"}}]])
            }
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: minimal valid exact-cache configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
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



=== TEST 2: reject config missing required redis (policy=redis then-clause)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({})

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/then clause did not match/



=== TEST 3: reject an out-of-range exact.ttl
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                exact = { ttl = 0 },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/ttl/



=== TEST 4: flush redis, then set route with ai-proxy + ai-cache (mock upstream)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

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
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4o"
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 5: cold request is a cache MISS and is proxied upstream
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ai-cache miss unique-prompt-5"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/
--- wait: 0.3



=== TEST 6: identical re-request is a HIT served from cache (upstream not called)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ai-cache miss unique-prompt-5"}]}
--- error_code: 200
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Age: \d+
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 7: fingerprint covers the client request AND the effective instance config (key.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local key = require("apisix.plugins.ai-cache.key")

            -- fingerprint() identifies the effective upstream request, so it reads
            -- both the client body and the picked instance (provider/options/override).
            local function fp(inst, body)
                local ctx = { ai_client_protocol = "openai-chat", var = {},
                              picked_ai_instance = inst }
                return key.fingerprint(ctx, body)
            end

            local inst   = { provider = "openai", options = {}, override = {} }
            local prompt = { model = "gpt-4o", messages = {{role="user", content="hi"}}, temperature = 0.2 }
            local base   = fp(inst, prompt)

            -- client fields the upstream would see: a change flips the fingerprint
            local other_messages = { model = "gpt-4o",      messages = {{role="user", content="bye"}} }
            local other_model    = { model = "gpt-4o-mini", messages = {{role="user", content="hi"}}  }
            local other_temp     = { model = "gpt-4o",      messages = {{role="user", content="hi"}}, temperature = 0.9 }
            local with_stream    = { model = "gpt-4o",      messages = {{role="user", content="hi"}}, temperature = 0.2, stream = true }

            assert(fp(inst, prompt)         == base, "identical request and config must match")
            assert(fp(inst, other_messages) ~= base, "different messages")
            assert(fp(inst, other_model)    ~= base, "different client model")
            assert(fp(inst, other_temp)     ~= base, "different temperature")
            assert(fp(inst, with_stream)    ~= base, "the stream flag is folded into the fingerprint (streaming and non-streaming cache separately)")

            -- instance config that ai-proxy applies upstream: a change flips it too
            local other_provider = { provider = "deepseek", options = {},                       override = {} }
            local forced_model   = { provider = "openai",   options = { model = "gpt-4o-mini" }, override = {} }
            local server_temp    = { provider = "openai",   options = { temperature = 0.9 },     override = {} }
            local llm_opts       = { provider = "openai",   options = {}, override = { llm_options = { max_tokens = 16 } } }
            local body_override  = { provider = "openai",   options = {}, override = { request_body = { ["openai-chat"] = { foo = "bar" } } } }
            local endpoint_a     = { provider = "openai",   options = {}, override = { endpoint = "http://host/a" } }
            local endpoint_b     = { provider = "openai",   options = {}, override = { endpoint = "http://host/b" } }

            assert(fp(other_provider, prompt) ~= base, "different provider")
            assert(fp(forced_model,   prompt) ~= base, "different effective model")
            assert(fp(server_temp,    prompt) ~= base, "different server-side options")
            assert(fp(llm_opts,       prompt) ~= base, "different override.llm_options")
            assert(fp(body_override,  prompt) ~= base, "different override.request_body")
            assert(fp(endpoint_a, prompt) ~= fp(endpoint_b, prompt), "different override.endpoint")

            -- a forced options.model overrides the client model, so the client model stops mattering
            assert(fp(forced_model, { messages = prompt.messages, model = "gpt-4o" })
                   == fp(forced_model, { messages = prompt.messages, model = "zzz" }),
                   "forced options.model makes the client model irrelevant")

            -- an explicit JSON null must encode stably (regression for the rapidjson null path)
            local with_null = core.json.decode(
                '{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}],"stop":null}')
            assert(fp(inst, with_null) == fp(inst, with_null), "null-bearing fingerprint must be stable")
            assert(fp(inst, with_null) ~= base, "an explicit null must change the fingerprint")

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: non-2xx upstream (no fixture -> 401) is a MISS
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"non-2xx-test-prompt"}]}
--- error_code: 401
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 9: same prompt with a valid fixture is still a MISS (the 401 was not cached)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"non-2xx-test-prompt"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 10: set route with a bypass_on header rule
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "bypass_on": [{"header": "X-AI-Cache-Bypass", "equals": "1"}]
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



=== TEST 11: a matching bypass_on header value is a BYPASS
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"bypass rule test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Cache-Bypass: 1
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 12: a non-matching bypass_on header value does not bypass (normal MISS)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"bypass-nonmatch-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Cache-Bypass: 0
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 13: set route with multiple bypass_on rules
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "bypass_on": [
                                {"header": "X-AI-Cache-Bypass", "equals": "1"},
                                {"header": "X-Debug", "equals": "on"}
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



=== TEST 14: any matching bypass_on rule triggers a BYPASS (second rule matches)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"any-rule-bypass-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Debug: on
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 15: set route with a tiny max_cache_body_size
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "max_cache_body_size": 10
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



=== TEST 16: cold request (response exceeds max_cache_body_size) is a MISS
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"body-size-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 17: same prompt is still a MISS (oversized response was not cached)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"body-size-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 18: set route isolating the cache by a request variable
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "include_vars": ["http_x_tenant"] }
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



=== TEST 19: tenant alpha cold request is a MISS (warms scope=alpha)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: alpha
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 20: same prompt, tenant beta is a MISS (not shared with alpha)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: beta
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 21: same prompt, tenant alpha is a HIT (its own scope persisted)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-Tenant: alpha
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 22: set route with a 1-second exact ttl
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "exact": { "ttl": 1 }
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



=== TEST 23: cold request is a MISS (cached with ttl=1), then wait past the ttl
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ttl-expiry-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 2



=== TEST 24: same prompt is a MISS again (entry expired)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ttl-expiry-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 25: set an anthropic-messages route (cross-protocol)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "anthropic",
                            "auth": { "header": { "x-api-key": "test-key" } },
                            "options": { "model": "claude-3-5-sonnet-20241022" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 26: anthropic cold request is a MISS
--- request
POST /v1/messages
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"cross-protocol test"}],"max_tokens":100}
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 27: identical anthropic re-request is a HIT (upstream not called)
--- request
POST /v1/messages
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"cross-protocol test"}],"max_tokens":100}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 28: set route whose redis is unreachable
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6390,
                            "redis_timeout": 200
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



=== TEST 29: redis unreachable fails open (request still proxied as MISS, no 5xx)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"redis-down failopen"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/
--- error_log
ai-cache: L1 lookup failed, fail-open as MISS



=== TEST 30: set route with cache_headers disabled
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_headers": false
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



=== TEST 31: cache_headers=false suppresses the X-AI-Cache-* headers
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cache-headers-off-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
! X-AI-Cache-Status
! X-AI-Cache-Age
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 32: set a default ai-proxy + ai-cache route (for status-code tests)
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 33: a 2xx that is not 200 (201) is a MISS and is proxied through
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"status-201-test-prompt"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 201
--- error_code: 201
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 34: same prompt with a 200 fixture is still a MISS (the 201 was not cached)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"status-201-test-prompt"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 35: set two openai routes (same model, default scope) sharing one Redis
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/cache-route-b",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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
passed



=== TEST 36: route 1 cold request is a MISS (warms scope=route=1)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-route isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 37: same prompt on route 2 is a MISS (not shared with route 1 by default)
--- request
POST /cache-route-b
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-route isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 38: same prompt on route 1 is a HIT (its own per-route scope persisted)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-route isolation test"}]}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 39: set both routes with share_across_routes enabled
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
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/cache-route-b",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
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
passed



=== TEST 40: route 1 cold request is a MISS (warms the shared scope)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-route share test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 41: same prompt on route 2 is a HIT (cache shared across routes)
--- request
POST /cache-route-b
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-route share test"}]}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 42: route with ai-cache but NO ai-proxy in front
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/v1/chat/completions",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1980": 1 }
                    },
                    "plugins": {
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 43: a request that never passed through ai-proxy is bypassed, not cached
--- request
POST /v1/chat/completions
{"model":"gpt-4o","messages":[{"role":"user","content":"no ai-proxy guard test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 44: route with ai-cache fail_mode=error and NO ai-proxy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/v1/chat/completions",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1980": 1 }
                    },
                    "plugins": {
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "fail_mode": "error"
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



=== TEST 45: fail_mode=error rejects a request that bypassed the AI proxy
--- request
POST /v1/chat/completions
{"model":"gpt-4o","messages":[{"role":"user","content":"fail_mode error guard test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 500
--- response_body_like eval
qr/must be used with the ai-proxy/



=== TEST 46: flush redis, then set one ai-proxy-multi route with two instances
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/multi",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "instance-gpt4o",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": { "header": { "Authorization": "Bearer test-key" } },
                                    "options": { "model": "gpt-4o" },
                                    "override": { "endpoint": "http://127.0.0.1:1980" }
                                },
                                {
                                    "name": "instance-gpt4o-mini",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": { "header": { "Authorization": "Bearer test-key" } },
                                    "options": { "model": "gpt-4o-mini" },
                                    "override": { "endpoint": "http://127.0.0.1:1980" }
                                }
                            ]
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 47: round-robin alternates instances, so each one caches independently
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- pipelined_requests eval
[
    "POST /multi\n" . '{"model":"gpt-4o","messages":[{"role":"user","content":"multi-instance isolation"}]}',
    "POST /multi\n" . '{"model":"gpt-4o","messages":[{"role":"user","content":"multi-instance isolation"}]}',
    "POST /multi\n" . '{"model":"gpt-4o","messages":[{"role":"user","content":"multi-instance isolation"}]}',
    "POST /multi\n" . '{"model":"gpt-4o","messages":[{"role":"user","content":"multi-instance isolation"}]}',
]
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers eval
[
    "X-AI-Cache-Status: MISS",
    "X-AI-Cache-Status: MISS",
    "X-AI-Cache-Status: HIT",
    "X-AI-Cache-Status: HIT",
]



=== TEST 48: flush redis, then two plain ai-proxy routes, same provider, different
options.model, shared cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/cache-route-b",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o-mini" },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
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
passed



=== TEST 49: route 1 cold request is a MISS (warms the shared scope under gpt-4o)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-model share test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 50: identical request on route 2 is a MISS, not a HIT (different effective
model is not shared even with share_across_routes)
--- request
POST /cache-route-b
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-model share test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 51: flush redis, then two plain ai-proxy routes, same provider and same
options.model, but different server-side options (temperature), shared cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o", "temperature": 0.2 },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/cache-route-b",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o", "temperature": 0.8 },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "cache_key": { "share_across_routes": true }
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
passed



=== TEST 52: route 1 cold request is a MISS (warms the shared scope under temperature=0.2)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-options share test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 53: identical client body on route 2 is a MISS, not a HIT (different
server-side options are not shared even with share_across_routes)
--- request
POST /cache-route-b
{"model":"gpt-4o","messages":[{"role":"user","content":"cross-options share test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 54: ai-proxy-multi route whose higher-priority instance always 5xxs and
falls back to a healthy instance (different effective endpoint)
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/fallback",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": ["http_5xx"],
                            "balancer": { "algorithm": "roundrobin" },
                            "instances": [
                                {
                                    "name": "primary-fail",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 2,
                                    "auth": { "header": { "Authorization": "Bearer test-key" } },
                                    "options": { "model": "gpt-4o" },
                                    "override": { "endpoint": "http://127.0.0.1:6731" }
                                },
                                {
                                    "name": "backup-ok",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": { "header": { "Authorization": "Bearer test-key" } },
                                    "options": { "model": "gpt-4o" },
                                    "override": { "endpoint": "http://127.0.0.1:1980" }
                                }
                            ]
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379
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



=== TEST 55: first request falls back to the healthy instance and is a MISS
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- request
POST /fallback
{"model":"gpt-4o","messages":[{"role":"user","content":"fallback poison test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 56: identical request is STILL a MISS -- the fallback instance's response
must not be cached under the originally-picked instance's key
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- request
POST /fallback
{"model":"gpt-4o","messages":[{"role":"user","content":"fallback poison test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 57: scope() escapes include_vars values so a tenant cannot forge another's scope (key.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")

            -- include_vars values are request-controlled (e.g. headers), so they
            -- must not be able to inject the ":"/"=" scope separators and shift
            -- field boundaries into another tenant's scope.
            local conf = { cache_key = { share_across_routes = true,
                                         include_vars = { "http_x_a", "http_x_b" } } }
            local function key_for(a, b)
                return key.build(conf, { var = { http_x_a = a, http_x_b = b } }, "fp")
            end

            -- baseline: identical values share a key, and plain values stay greppable
            assert(key_for("acme", "us") == key_for("acme", "us"),
                   "identical scope values must produce the same key")
            assert(key_for("acme", "us"):find("http_x_a=acme", 1, true),
                   "plain values must stay readable in the key")

            -- two tenants whose raw "http_x_a=<a>:http_x_b=<b>" join both collapse
            -- to "http_x_a=x:http_x_b=yZ:http_x_b=" unless the values are escaped
            local tenant1 = key_for("x:http_x_b=yZ", "")
            local tenant2 = key_for("x", "yZ:http_x_b=")
            assert(tenant1 ~= tenant2,
                   "separator-injecting values must not collide into one scope")
            ngx.say("passed")
        }
    }
--- response_body
passed
