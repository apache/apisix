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
});

run_tests();

__DATA__

=== TEST 1: key.build is deterministic for identical bodies
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello" }} })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 2: changing the model changes the key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o",      messages = {{ role = "user", content = "hello" }} })
            local b = key.build({ model = "gpt-4o-mini", messages = {{ role = "user", content = "hello" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 3: changing message content changes the key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello"   }} })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "goodbye" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 4: message-array order matters (turn-order is semantic)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {
                { role = "user",      content = "A" },
                { role = "assistant", content = "B" },
            }})
            local b = key.build({ model = "gpt-4o", messages = {
                { role = "assistant", content = "B" },
                { role = "user",      content = "A" },
            }})
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 5: identical bodies built in different declaration orders share a key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- Build the same logical body two different ways. dkjson
            -- sorts object keys so the canonical encoding is identical.
            local a = key.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "hi" }},
            })
            local b = key.build({
                messages = {{ content = "hi", role = "user" }},
                model    = "gpt-4o",
            })
            ngx.say(a == b and "ok" or "MISMATCH")
        }
    }
--- response_body
ok



=== TEST 6: vision messages with different image URLs produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{
                role = "user",
                content = {
                    { type = "text",      text = "what is this" },
                    { type = "image_url", image_url = { url = "http://x/cat.png" } },
                },
            }}})
            local b = key.build({ model = "gpt-4o", messages = {{
                role = "user",
                content = {
                    { type = "text",      text = "what is this" },
                    { type = "image_url", image_url = { url = "http://x/dog.png" } },
                },
            }}})
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 7: vision messages with identical image URLs produce the same key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local block = {
                { type = "text",      text = "what is this" },
                { type = "image_url", image_url = { url = "http://x/cat.png" } },
            }
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = block }} })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = block }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 8: temperature 0.2 vs 0.7 produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local base = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            base.temperature = 0.2
            local a = key.build(base)
            base.temperature = 0.7
            local b = key.build(base)
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 9: temperature 0.2 and 0.2000001 collapse to the same key (milli-quantise)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = 0.2 })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = 0.2000001 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 10: quantise pathological - NaN and negative both map to 0 (SAME key)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local nan = 0/0
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = nan })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = -1 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 11: quantise pathological - inf and overflow both saturate to u32 max (SAME key)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = math.huge })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = 5000000 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 12: quantise pathological - NaN(->0) vs 0.7(->700) produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local nan = 0/0
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = nan })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, temperature = 0.7 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 13: tools present vs absent produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local base = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            local a = key.build(base)
            base.tools = {{ type = "function", ["function"] = { name = "get_weather" } }}
            local b = key.build(base)
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 14: tools array order matters (different order -> different key)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local tool_a = { type = "function", ["function"] = { name = "get_weather" } }
            local tool_b = { type = "function", ["function"] = { name = "get_time" } }
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, tools = { tool_a, tool_b } })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, tools = { tool_b, tool_a } })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 15: response_format type "json_object" vs "text" produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, response_format = { type = "json_object" } })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, response_format = { type = "text" } })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 16: seed 42 vs 43 produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, seed = 42 })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, seed = 43 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 17: nested object key-order in tools is canonicalised (SAME key)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- Tool declared with parameters keys in different order; stably_encode
            -- must sort them recursively so both produce the same fingerprint.
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                tools = {{
                    type = "function",
                    ["function"] = {
                        name = "search",
                        parameters = { type = "object", properties = { q = { type = "string" } } },
                    },
                }},
            })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                tools = {{
                    ["function"] = {
                        parameters = { properties = { q = { type = "string" } }, type = "object" },
                        name = "search",
                    },
                    type = "function",
                }},
            })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 18: opts.instance "a" vs "b" produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local req = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            local a = key.build(req, { instance = "a" })
            local b = key.build(req, { instance = "b" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 19: opts.protocol "openai-chat" vs "anthropic-messages" produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local req = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            local a = key.build(req, { protocol = "openai-chat" })
            local b = key.build(req, { protocol = "anthropic-messages" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 20: stream is excluded from the key (gated out before keying, never cached)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- Streaming requests are skipped before a key is ever built, so
            -- `stream` must not affect the key (matches aisix-cache).
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, stream = true })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, stream = false })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 21: logit_bias differences produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- logit_bias reshapes token probabilities, so it changes the completion;
            -- two requests differing only in logit_bias must not share a slot.
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                logit_bias = { ["50256"] = -100 } })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                logit_bias = { ["50256"] = 100 } })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 22: parallel_tool_calls true vs false produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                parallel_tool_calls = true })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                parallel_tool_calls = false })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 23: presence_penalty 0 vs -1.0 produce different keys (signed field, not quantised)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- Regression: presence_penalty is signed ([-2, 2]). It must be hashed
            -- exactly, not milli-quantised (which would fold every negative onto 0
            -- and serve a wrong cached response).
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                presence_penalty = 0 })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                presence_penalty = -1.0 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 24: two distinct negative presence_penalty values produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                presence_penalty = -1.5 })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                presence_penalty = -0.5 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 25: two distinct negative frequency_penalty values produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                frequency_penalty = -1.5 })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                frequency_penalty = -0.5 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 26: max_completion_tokens 100 vs 4000 produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "o3", messages = {{ role = "user", content = "hi" }},
                max_completion_tokens = 100 })
            local b = key.build({ model = "o3", messages = {{ role = "user", content = "hi" }},
                max_completion_tokens = 4000 })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 27: reasoning_effort "low" vs "high" produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "o3", messages = {{ role = "user", content = "hi" }},
                reasoning_effort = "low" })
            local b = key.build({ model = "o3", messages = {{ role = "user", content = "hi" }},
                reasoning_effort = "high" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 28: legacy function_call differences produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                function_call = "auto" })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }},
                function_call = "none" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 29: opts.route_id "1" vs "2" produce different keys (per-route scoping)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- APISIX resolves the upstream per route, so the same body on two
            -- routes may hit different upstreams; the key must not collide.
            local req = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            local a = key.build(req, { protocol = "openai-chat", instance = "ai-proxy-openai", route_id = "1" })
            local b = key.build(req, { protocol = "openai-chat", instance = "ai-proxy-openai", route_id = "2" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 30: the OpenAI `user` field is excluded (callers share a cache entry)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- `user` is a caller identifier that does not change the completion;
            -- excluding it lets different callers share one entry.
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, user = "alice" })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, user = "bob" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 31: an unlisted output-affecting field still scopes the key (hash-all, not whitelist)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- A field not in any explicit whitelist (e.g. a future/less-common
            -- OpenAI param) must still change the key, since the whole body is
            -- hashed. `service_tier` stands in for "any unlisted field".
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, service_tier = "default" })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, service_tier = "flex" })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff
