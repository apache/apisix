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



=== TEST 20: req.stream true vs false produce different keys
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, stream = true })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hi" }}, stream = false })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff
