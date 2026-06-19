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



=== TEST 3: reject unknown layer value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "nonsense" },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/layers/



=== TEST 4: flush redis, then set route with ai-proxy + ai-cache (mock upstream)
--- config
    location /t {
        content_by_lua_block {
            local redis = require("resty.redis")
            local red = redis:new()
            red:set_timeout(1000)
            local ok, rerr = red:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", rerr)
                return
            end
            red:flushall()

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



=== TEST 7: fingerprint sensitivity (key.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local function ctx(model)
                return { ai_client_protocol = "openai-chat", var = { request_llm_model = model } }
            end
            local function fp(body)
                return key.fingerprint(ctx(body.model), body)
            end

            local base   = { model="gpt-4o",      messages={{role="user", content="hi"}}, temperature=0.2 }
            local same   = { model="gpt-4o",      messages={{role="user", content="hi"}}, temperature=0.2 }
            local msg2   = { model="gpt-4o",      messages={{role="user", content="yo"}}, temperature=0.2 }
            local model2 = { model="gpt-4o-mini", messages={{role="user", content="hi"}}, temperature=0.2 }
            local temp2  = { model="gpt-4o",      messages={{role="user", content="hi"}}, temperature=0.7 }
            local tools2 = { model="gpt-4o",      messages={{role="user", content="hi"}}, temperature=0.2,
                             tools={{ type="function", ["function"]={ name="f" } }} }

            local b = fp(base)
            assert(fp(same)   == b, "identical bodies must share a fingerprint")
            assert(fp(msg2)   ~= b, "changed message must change the fingerprint")
            assert(fp(model2) ~= b, "changed model must change the fingerprint")
            assert(fp(temp2)  ~= b, "changed temperature must change the fingerprint")
            assert(fp(tools2) ~= b, "changed tools must change the fingerprint")
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



=== TEST 10: set route with a cache_bypass variable rule
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
                            "cache_bypass": ["$http_x_ai_cache_bypass"]
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



=== TEST 11: a non-empty, non-"0" cache_bypass value is a BYPASS
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"bypass rule test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Cache-Bypass: 1
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 12: a cache_bypass value of "0" does not bypass (normal MISS)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"bypass-zero-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Cache-Bypass: 0
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 13: set route with a tiny max_cache_body_size
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



=== TEST 14: cold request (response exceeds max_cache_body_size) is a MISS
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"body-size-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 15: same prompt is still a MISS (oversized response was not cached)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"body-size-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 16: set route isolating the cache by a request variable
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



=== TEST 17: tenant alpha cold request is a MISS (warms scope=alpha)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: alpha
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 18: same prompt, tenant beta is a MISS (not shared with alpha)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: beta
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 19: same prompt, tenant alpha is a HIT (its own scope persisted)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"scope isolation test"}]}
--- more_headers
X-Tenant: alpha
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 20: set route with a 1-second exact ttl
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



=== TEST 21: cold request is a MISS (cached with ttl=1), then wait past the ttl
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ttl-expiry-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 2



=== TEST 22: same prompt is a MISS again (entry expired)
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"ttl-expiry-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 23: set an anthropic-messages route (cross-protocol)
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



=== TEST 24: anthropic cold request is a MISS
--- request
POST /v1/messages
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"cross-protocol test"}],"max_tokens":100}
--- more_headers
X-AI-Fixture: anthropic/messages-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 25: identical anthropic re-request is a HIT (upstream not called)
--- request
POST /v1/messages
{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"cross-protocol test"}],"max_tokens":100}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT



=== TEST 26: set route whose redis is unreachable
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



=== TEST 27: redis unreachable fails open (request still proxied as MISS, no 5xx)
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
ai-cache: redis unavailable, fail-open as MISS



=== TEST 28: set route with cache_headers disabled
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



=== TEST 29: cache_headers=false suppresses the X-AI-Cache-* headers
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"cache-headers-off-test"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status:
X-AI-Cache-Age:
--- response_body_like eval
qr/1 \+ 1 = 2/
