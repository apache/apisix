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

# Real text-embedding-3-small responses (captured at dimensions=64) live as
# fixtures under t/fixtures/openai/embeddings-*.json, and the mock that replays
# them by prompt lives in t/lib/ai_cache_mock.lua -- so every HIT/MISS/threshold
# decision is driven by genuine embedding geometry, hermetically:
#   cos(capital, capital_city) = 0.922   (paraphrase  -> HIT at threshold 0.9)
#   cos(capital, largest_city) = 0.706   (related     -> the real threshold knee)
#   cos(capital, tire)         = -0.148  (unrelated   -> always a MISS)

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

    # Only the embedding call is mocked (the chat completion uses the shared
    # :1980 X-AI-Fixture upstream); the mock logic lives in lib/ai_cache_mock.lua.
    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 6724;
        default_type 'application/json';

        location /v1/embeddings {
            content_by_lua_block { require("lib.ai_cache_mock").embeddings() }
        }
        location /v1/embeddings-broken {
            content_by_lua_block { require("lib.ai_cache_mock").broken() }
        }
        location /v1/embeddings-malformed {
            content_by_lua_block { require("lib.ai_cache_mock").malformed() }
        }
        location /v1/embeddings-openai {
            content_by_lua_block { require("lib.ai_cache_mock").embeddings_openai() }
        }
        location /v1/embeddings-azure {
            content_by_lua_block { require("lib.ai_cache_mock").embeddings_azure() }
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: layers defaults to ["exact"]; a minimal exact-only config is valid
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({ redis_host = "127.0.0.1" })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 2: an explicit layers=["exact"] is valid (no semantic block required)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact" },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 3: layers=["exact","semantic"] without a semantic block is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/allOf 1 failed: then clause did not match/



=== TEST 4: a full openai semantic config is valid
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    similarity_threshold = 0.9,
                    embedding = { openai = {
                        endpoint   = "https://api.openai.com/v1/embeddings",
                        model      = "text-embedding-3-small",
                        api_key    = "test-key",
                        dimensions = 1536,
                    } },
                    vector_search = { redis = { index = "ai-cache" } },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 5: a full azure_openai semantic config is valid (endpoint+api_key required)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    embedding = { azure_openai = {
                        endpoint = "https://my.openai.azure.com/.../embeddings?api-version=2024-02-01",
                        api_key  = "test-key",
                    } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 6: layers=["semantic"] without "exact" is rejected (exact is always required)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "semantic" },
                semantic = {
                    embedding = { openai = { model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "layers" validation failed: failed to check contains/



=== TEST 7: distance_metric "euclidean" is rejected (cosine-only in this layer)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    distance_metric = "euclidean",
                    embedding = { openai = { model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "distance_metric" validation failed: matches none of the enum values/



=== TEST 8: similarity_threshold above 1 is rejected (must be within [0, 1])
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    similarity_threshold = 1.5,
                    embedding = { openai = { model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "similarity_threshold" validation failed: expected 1\.5 to be at most 1/



=== TEST 9: semantic.ttl below 1 is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    ttl = 0,
                    embedding = { openai = { model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "ttl" validation failed: expected 0 to be at least 1/



=== TEST 10: embedding must name exactly one provider -- neither is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    embedding = {},
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "embedding" validation failed: value should match only one schema, but matches none/



=== TEST 11: embedding must name exactly one provider -- both is rejected (oneOf)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    embedding = {
                        openai       = { model = "text-embedding-3-small", api_key = "test-key" },
                        azure_openai = { endpoint = "https://a.b/e", api_key = "test-key" },
                    },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "embedding" validation failed: value should match only one schema, but matches both schemas 1 and 2/



=== TEST 12: match.message_countback below 1 is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = { "exact", "semantic" },
                semantic = {
                    match = { message_countback = 0 },
                    embedding = { openai = { model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body eval
qr/property "message_countback" validation failed: expected 0 to be at least 1/



=== TEST 13: context_fingerprint ignores message TEXT but reacts to model/params (key.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")

            -- the context fingerprint deduplicates by the EFFECTIVE request context
            -- (provider/model/params/instance) with the message wording removed, so a
            -- paraphrase collapses to one fingerprint while a parameter change does not.
            local function ctx()
                return { ai_client_protocol = "openai-chat",
                         picked_ai_instance = { provider = "openai",
                                                options = { model = "gpt-4o" }, override = {} },
                         var = {} }
            end
            local a = key.context_fingerprint(ctx(), { model = "gpt-4o", temperature = 0.2,
                messages = {{ role = "user", content = "how do I return an item?" }} })
            local b = key.context_fingerprint(ctx(), { model = "gpt-4o", temperature = 0.2,
                messages = {{ role = "user", content = "what is the return policy?" }} })
            local c = key.context_fingerprint(ctx(), { model = "gpt-4o", temperature = 0.9,
                messages = {{ role = "user", content = "how do I return an item?" }} })

            assert(a == b, "differently-worded prompts must share one context fingerprint")
            assert(a ~= c, "a parameter change (temperature) must flip the context fingerprint")
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: partition is stable and isolates by scope and effective model (key.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")

            -- partition = sha256(scope | context_repr); it is what segregates the L2
            -- vector index so a paraphrase can only ever hit within its own
            -- tenant + route + effective-model cell.
            local function ctx(tenant, model)
                return { ai_client_protocol = "openai-chat",
                         picked_ai_instance = { provider = "openai",
                                                options = { model = model or "gpt-4o" }, override = {} },
                         var = { route_id = "1", http_x_tenant = tenant } }
            end
            local body = { model = "gpt-4o", messages = {{ role = "user", content = "hi" }} }
            local conf = { cache_key = { include_vars = { "http_x_tenant" } } }

            assert(key.partition(conf, ctx("acme"), body) == key.partition(conf, ctx("acme"), body),
                   "the same inputs must produce the same partition")
            assert(key.partition(conf, ctx("acme"), body) ~= key.partition(conf, ctx("globex"), body),
                   "an include_vars (tenant) change must change the partition")
            assert(key.partition(conf, ctx("acme", "gpt-4o"), body)
                       ~= key.partition(conf, ctx("acme", "gpt-4o-mini"), body),
                   "a different effective model must change the partition")
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 15: extract_embed_text keeps the last user message, skipping system/assistant (semantic.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            local msgs = {
                { role = "system",    content = "you are helpful" },
                { role = "user",      content = "first question" },
                { role = "assistant", content = "an answer" },
                { role = "user",      content = "the real question" },
            }
            -- countback 1 -> only the most recent user message
            ngx.say(semantic.extract_embed_text(msgs, { message_countback = 1 }))
            -- countback 2 -> the two most recent kept (user) messages, newline-joined
            ngx.say(semantic.extract_embed_text(msgs, { message_countback = 2 }))
        }
    }
--- response_body
the real question
first question
the real question



=== TEST 16: extract_embed_text flattens multimodal text blocks, dropping non-text (semantic.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            local msgs = {{ role = "user", content = {
                { type = "text",      text = "describe" },
                { type = "image_url", image_url = { url = "http://x/y.png" } },
                { type = "text",      text = "this image" },
            }}}
            ngx.say(semantic.extract_embed_text(msgs, {}))
        }
    }
--- response_body
describe
this image



=== TEST 17: extract_embed_text honours ignore flags (system kept when not ignored) (semantic.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            local msgs = {
                { role = "system", content = "system preamble" },
                { role = "user",   content = "the question" },
            }
            -- default: system prompts ignored -> only the user message
            ngx.say(semantic.extract_embed_text(msgs, { message_countback = 2 }))
            ngx.say("---")
            -- opt-in: keep system prompts -> both, newline-joined
            ngx.say(semantic.extract_embed_text(msgs,
                { message_countback = 2, ignore_system_prompts = false }))
        }
    }
--- response_body
the question
---
system preamble
the question



=== TEST 18: openai embeddings driver extracts data[1].embedding (real 1536-dim vector) + sends Bearer
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv  = require("apisix.plugins.ai-cache.embeddings.openai")
            -- the mock returns 401 unless Authorization: Bearer test-key is present,
            -- so a successful vector also proves the driver sent the bearer token.
            local vec, err = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:6724/v1/embeddings-openai",
                  model = "text-embedding-3-small", api_key = "test-key" },
                "What is the capital of France?", http.new(), false)
            if not vec then ngx.say("err:", err); return end
            -- the real captured "capital" embedding (text-embedding-3-small)
            ngx.say("dim=", #vec)
            ngx.say(string.format("v1=%.6f v2=%.6f v3=%.6f", vec[1], vec[2], vec[3]))
        }
    }
--- response_body
dim=64
v1=0.183716 v2=0.069519 v3=0.124023



=== TEST 19: openai embeddings driver fails closed on a non-2xx response
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv  = require("apisix.plugins.ai-cache.embeddings.openai")
            local vec = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:6724/v1/embeddings-broken",
                  model = "text-embedding-3-small", api_key = "test-key" },
                "hi", http.new(), false)
            ngx.say(vec and "got-vec" or "nil-on-error")
        }
    }
--- response_body
nil-on-error



=== TEST 20: openai embeddings driver rejects a malformed (well-formed-HTTP) body
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv  = require("apisix.plugins.ai-cache.embeddings.openai")
            local vec, err = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:6724/v1/embeddings-malformed",
                  model = "text-embedding-3-small", api_key = "test-key" },
                "hi", http.new(), false)
            ngx.say(vec and "got-vec" or "nil-on-error")
            ngx.say(err)
        }
    }
--- response_body
nil-on-error
malformed embeddings response



=== TEST 21: azure_openai embeddings driver sends api-key (not Authorization), returns the real vector
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv  = require("apisix.plugins.ai-cache.embeddings.azure_openai")
            -- the mock 401s without api-key and 400s if Authorization is present,
            -- so a vector here proves the azure auth scheme is used exclusively.
            local vec, err = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:6724/v1/embeddings-azure", api_key = "test-key" },
                "What is the capital of France?", http.new(), false)
            if not vec then ngx.say("err:", err); return end
            ngx.say("dim=", #vec)
            ngx.say(string.format("v1=%.6f v2=%.6f v3=%.6f", vec[1], vec[2], vec[3]))
        }
    }
--- response_body
dim=64
v1=0.183716 v2=0.069519 v3=0.124023



=== TEST 22: azure_openai embeddings driver fails closed on a non-2xx response
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv  = require("apisix.plugins.ai-cache.embeddings.azure_openai")
            local vec = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:6724/v1/embeddings-broken", api_key = "test-key" },
                "hi", http.new(), false)
            ngx.say(vec and "got-vec" or "nil-on-error")
        }
    }
--- response_body
nil-on-error



=== TEST 23: pack_float32 produces a 4-bytes-per-element little-endian blob (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local blob = vs.pack_float32({ 1.0, 0.0, 0.0 })
            ngx.say(type(blob), ":", #blob)
            -- 1.0f little-endian = 00 00 80 3f
            ngx.say(string.byte(blob, 3), ",", string.byte(blob, 4))
        }
    }
--- response_body
string:12
128,63



=== TEST 24: ensure_index creates the index and is idempotent on a second call (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            red:flushdb()
            local tgt = "127.0.0.1#6379#0"
            assert(vs.ensure_index(red, tgt, "ut-create:idx:3", "ut-create:l2:", 3))
            assert(vs.ensure_index(red, tgt, "ut-create:idx:3", "ut-create:l2:", 3))  -- idempotent
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 25: upsert + knn_search round-trip returns the nearest doc by cosine distance (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            red:flushdb()
            local tgt = "127.0.0.1#6379#0"
            assert(vs.ensure_index(red, tgt, "ut-knn:idx:3", "ut-knn:l2:", 3))

            assert(vs.upsert(red, "ut-knn:l2:p1:near",
                { partition = "p1", embedding = vs.pack_float32({ 1.0, 0.0, 0.0 }),
                  response = [[{"answer":"NEAR"}]], created_at = 100 }, 600))
            assert(vs.upsert(red, "ut-knn:l2:p1:far",
                { partition = "p1", embedding = vs.pack_float32({ 0.0, 1.0, 0.0 }),
                  response = [[{"answer":"FAR"}]], created_at = 100 }, 600))

            local hit, err = vs.knn_search(red, tgt, "ut-knn:idx:3", "p1", { 0.99, 0.01, 0.0 }, 1)
            if not hit then ngx.say("no-hit:", err or ""); return end
            ngx.say(hit.response)
            ngx.say(hit.distance < 0.01 and "near-distance" or ("dist=" .. hit.distance))
        }
    }
--- response_body
{"answer":"NEAR"}
near-distance



=== TEST 26: knn_search returns nil and no error when the partition holds no docs (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            red:flushdb()
            local tgt = "127.0.0.1#6379#0"
            assert(vs.ensure_index(red, tgt, "ut-empty:idx:3", "ut-empty:l2:", 3))
            -- partitions are sha256 hex in production; use a hex-shaped value here
            local hit, err = vs.knn_search(red, tgt, "ut-empty:idx:3", "deadbeef", { 1, 0, 0 }, 1)
            ngx.say(hit == nil and not err and "clean-miss" or "unexpected")
        }
    }
--- response_body
clean-miss



=== TEST 27: knn_search is partition-scoped -- an identical vector in another partition is invisible (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            red:flushdb()
            local tgt = "127.0.0.1#6379#0"
            assert(vs.ensure_index(red, tgt, "ut-part:idx:3", "ut-part:l2:", 3))

            -- two docs with the SAME vector but different partition tags
            assert(vs.upsert(red, "ut-part:l2:p1:d1",
                { partition = "p1", embedding = vs.pack_float32({ 1.0, 0.0, 0.0 }),
                  response = [[{"answer":"P1"}]], created_at = 100 }, 600))
            assert(vs.upsert(red, "ut-part:l2:p2:d2",
                { partition = "p2", embedding = vs.pack_float32({ 1.0, 0.0, 0.0 }),
                  response = [[{"answer":"P2"}]], created_at = 100 }, 600))

            local hit = vs.knn_search(red, tgt, "ut-part:idx:3", "p1", { 1, 0, 0 }, 1)
            ngx.say(hit and hit.response or "no-hit")
            -- querying a partition with no docs must not leak p1/p2's identical vector
            local other = vs.knn_search(red, tgt, "ut-part:idx:3", "p3", { 1, 0, 0 }, 1)
            ngx.say(other == nil and "isolated" or "leaked")
        }
    }
--- response_body
{"answer":"P1"}
isolated



=== TEST 28: set a semantic route (exact+semantic, default "ai-cache" index, threshold 0.9)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": {} }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 29: a cold prompt ("capital of France") is a semantic MISS and is proxied upstream
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/
--- wait: 0.5



=== TEST 30: a real paraphrase ("capital city of France", cos 0.922) is a semantic L2 HIT
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d
X-AI-Cache-Age: \d+
--- response_body_like eval
qr/1 \+ 1 = 2/
--- wait: 0.3



=== TEST 31: repeating the paraphrase is now an exact L1 HIT (backfill -- no similarity header)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers
X-AI-Cache-Status: HIT
! X-AI-Cache-Similarity
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 32: an unrelated prompt ("flat car tire", cos -0.148) is a MISS (far below threshold)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"How do I change a flat car tire?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/
--- wait: 0.3



=== TEST 33: the default "ai-cache:l2:" namespace was populated by the semantic writes
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            local keys = red:keys("ai-cache:l2:*")
            red:close()
            ngx.say("default-l2=", (keys and #keys > 0) and "present" or "absent")
        }
    }
--- response_body
default-l2=present



=== TEST 34: set a single semantic route with NO options.model (effective model = body model)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "override": { "endpoint": "http://127.0.0.1:1980" }
                        },
                        "ai-cache": {
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "idx-model" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 35: gpt-4o cold request is a MISS (warms the gpt-4o partition)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 36: gpt-4o-mini with the same prompt and same vector is still a MISS (partition is model-scoped)
--- request
POST /semantic
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 37: a gpt-4o paraphrase is a semantic HIT (gpt-4o's L2 partition is intact and isolated)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d



=== TEST 38: set a semantic route isolated per-tenant via include_vars
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "cache_key": { "include_vars": ["http_x_tenant"] },
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "idx-tenant" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 39: tenant acme cold request is a MISS (warms the acme scope)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: acme
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 40: tenant globex with the same prompt and vector is a MISS (no cross-tenant semantic leak)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-Tenant: globex
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 41: a tenant acme paraphrase is a semantic HIT (acme's own scope persisted)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- more_headers
X-Tenant: acme
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d



=== TEST 42: set a semantic route whose embedding endpoint always 5xxs (fail-open)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings-broken",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "idx-failopen" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 43: a broken embedding provider fails open to a MISS; exact (L1) still warms
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/1 \+ 1 = 2/
--- error_log
ai-cache: embedding failed, fail-open as MISS
--- wait: 0.5



=== TEST 44: the identical request is an exact L1 HIT (the broken embedder never corrupted L1)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- response_headers
X-AI-Cache-Status: HIT
! X-AI-Cache-Similarity
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 45: set a semantic route with a custom vector_search index ("myidx")
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "myidx" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 46: custom-index cold request is a MISS (warms L2 under "myidx")
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 47: a paraphrase is a semantic HIT served from the custom index
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d



=== TEST 48: L2 docs live under the custom "myidx:l2:" prefix, never the default "ai-cache:l2:"
--- config
    location /t {
        content_by_lua_block {
            local redis_util = require("apisix.utils.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            local myidx   = red:keys("myidx:l2:*")
            local default = red:keys("ai-cache:l2:*")
            red:close()
            ngx.say("myidx-l2=",   (myidx   and #myidx   > 0) and "present" or "absent")
            ngx.say("default-l2=", (default and #default > 0) and "present" or "none")
        }
    }
--- response_body
myidx-l2=present
default-l2=none



=== TEST 49: set a strict route -- similarity_threshold 0.8 (above the real related-question score)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.8,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "idx-thrhi" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 50: anchor cold request is a MISS (stores the "capital" embedding)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 51: the related question ("largest city", cos 0.706) is a MISS under the 0.8 threshold
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the largest city in France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.3



=== TEST 52: set the same scenario with a lenient similarity_threshold of 0.6
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.6,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": { "index": "idx-thrlo" } }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 53: anchor cold request is a MISS (stores the "capital" embedding)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 54: the same related question is a HIT under the 0.6 threshold (real similarity 0.706)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the largest city in France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.70\d\d
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 55: context_messages returns the messages the embedding does NOT cover (semantic.lua unit)
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            local msgs = {
                { role = "system",    content = "a document" },
                { role = "user",      content = "first question" },
                { role = "assistant", content = "an answer" },
                { role = "user",      content = "the real question" },
            }
            -- default match embeds only the last user message; everything else
            -- is response-determining context that must isolate the partition
            local ctx = semantic.context_messages(msgs, { message_countback = 1 })
            local out = {}
            for _, m in ipairs(ctx) do out[#out + 1] = m.role .. ":" .. m.content end
            ngx.say(table.concat(out, ","))
            -- opting every message INTO the embedding leaves no separate context
            local all = semantic.context_messages(msgs,
                { message_countback = 4, ignore_system_prompts = false,
                  ignore_assistant_prompts = false })
            ngx.say(#all == 0 and "empty" or "non-empty")
        }
    }
--- response_body
system:a document,user:first question,assistant:an answer
empty



=== TEST 56: set a semantic route for the doc-Q&A regression (default match, threshold 0.9)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": {} }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 57: doc A + a generic question is a cold MISS (warms doc A's partition)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"system","content":"Document A: Paris is the capital of France."},{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 58: the SAME question under a different document (doc B) is a MISS, not a cross-context HIT
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"system","content":"Document B: Berlin is the capital of Germany."},{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 59: a paraphrase under the SAME document (doc A) still hits L2 (context preserved, wording fuzzy)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"system","content":"Document A: Paris is the capital of France."},{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 60: semantic L2 bypasses a protocol whose canonical form is lossy (openai-responses)
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            -- the gate returns before any embedding work, so conf/body are
            -- never touched; an unsupported protocol must fail open as no-L2
            local ctx = { ai_client_protocol = "openai-responses" }
            local vec = semantic.embed_query(nil, ctx, nil)
            ngx.say(vec == nil and "bypassed" or "engaged")
            ngx.say(ctx.ai_cache_embedding == nil and "no-embedding" or "embedded")
        }
    }
--- response_body
bypassed
no-embedding



=== TEST 61: a semantic block without "semantic" in layers is accepted (inactive), not rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            -- a full, valid semantic block but layers left at the default
            -- ["exact"]: allowed so the config can be staged/feature-flagged
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                semantic = {
                    embedding = { openai = {
                        model = "text-embedding-3-small", api_key = "test-key" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 62: set a semantic route for the multimodal-bypass regression (threshold 0.9)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/semantic",
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
                            "layers": ["exact", "semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": {
                                    "openai": {
                                        "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                        "model": "text-embedding-3-small",
                                        "api_key": "test-key"
                                    }
                                },
                                "vector_search": { "redis": {} }
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 63: a text-only prompt warms L2 with the "capital" vector (cold MISS)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 64: the SAME text carried alongside an image block bypasses L2 (a MISS, not a cross-modal L2 hit)
--- request
POST /semantic
{"model":"gpt-4o","messages":[{"role":"user","content":[{"type":"text","text":"What is the capital of France?"},{"type":"image_url","image_url":{"url":"https://example.com/paris.jpg"}}]}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 65: ensure_index memo is scoped per Redis target, not by index name alone (vector-search unit)
--- config
    location /t {
        content_by_lua_block {
            -- Unit-level on purpose: the bug only shows across two Redis servers
            -- (RediSearch forbids FT.CREATE on db!=0) and self-heals end-to-end.
            -- Model a second target that lacks the index via FT.DROPINDEX.
            local redis_util = require("apisix.utils.redis")
            local vs = require("apisix.plugins.ai-cache.vector-search.redis")
            local red = assert(redis_util.new({
                redis_host = "127.0.0.1", redis_port = 6379, redis_database = 0 }))
            red:flushdb()
            local index = "tgt-scope:idx:3"
            -- ensure against target A: the per-worker memo records (A|index)
            assert(vs.ensure_index(red, "hostA#6379#0", index, "tgt-scope:l2:", 3))
            -- drop the index; a different target B has never had it created
            red[ "FT.DROPINDEX" ](red, index)
            -- target B must NOT be served by target A's memo entry -- it must
            -- re-issue FT.CREATE (index-name-only keying would wrongly skip here)
            assert(vs.ensure_index(red, "hostB#6379#0", index, "tgt-scope:l2:", 3))
            -- proof B's create really happened: a search is a clean miss, not the
            -- "no such index" error a memo collision would leave behind
            local hit, err = vs.knn_search(red, "hostB#6379#0", index, "deadbeef", { 1, 0, 0 }, 1)
            ngx.say(hit == nil and not err and "recreated-for-target-B"
                    or ("skipped:" .. (err or "unexpected-hit")))
        }
    }
--- response_body
recreated-for-target-B
