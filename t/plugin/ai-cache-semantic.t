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
    my $cfg = <<_EOC_;
plugins:
  - ai-proxy
  - ai-cache
_EOC_
    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $cfg);
    }
});

run_tests();

__DATA__

=== TEST 1: layers defaults to ["exact"]; minimal exact config still valid
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



=== TEST 2: layers=["exact","semantic"] without a semantic block is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = {"exact", "semantic"},
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 3: full semantic config is valid
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = {"exact", "semantic"},
                semantic = {
                    embedding = { openai = {
                        endpoint = "https://api.openai.com/v1/embeddings",
                        model = "text-embedding-3-small",
                        api_key = "sk-x", dimensions = 1536 } },
                    vector_search = { redis = { index = "ai-cache" } },
                },
            })
            ngx.say(ok and "passed" or err)
        }
    }
--- response_body
passed



=== TEST 4: distance_metric "euclidean" is rejected (cosine-only this PR)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                redis_host = "127.0.0.1",
                layers = {"exact", "semantic"},
                semantic = {
                    distance_metric = "euclidean",
                    embedding = { openai = { model = "m", api_key = "k" } },
                    vector_search = { redis = {} },
                },
            })
            ngx.say(ok and "passed" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 5: context_fingerprint ignores message TEXT but reacts to model/params
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local function ctx()
                return { ai_client_protocol = "openai-chat",
                         picked_ai_instance = { provider = "openai", options = { model = "gpt-4o-mini" } },
                         var = { request_llm_model = "gpt-4o-mini" } }
            end
            local a = key.context_fingerprint(ctx(), { model = "gpt-4o-mini",
                messages = {{ role = "user", content = "how do I return an item?" }}, temperature = 0.2 })
            local b = key.context_fingerprint(ctx(), { model = "gpt-4o-mini",
                messages = {{ role = "user", content = "what is the return policy?" }}, temperature = 0.2 })
            local c = key.context_fingerprint(ctx(), { model = "gpt-4o-mini",
                messages = {{ role = "user", content = "how do I return an item?" }}, temperature = 0.9 })
            ngx.say(a == b and "msg-text-ignored" or "msg-text-affects")
            ngx.say(a ~= c and "params-matter" or "params-ignored")
        }
    }
--- response_body
msg-text-ignored
params-matter



=== TEST 6: partition is stable and isolation-sensitive
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local function ctx(tenant)
                return { ai_client_protocol = "openai-chat",
                         picked_ai_instance = { provider = "openai", options = { model = "m" } },
                         var = { route_id = "1", http_x_tenant = tenant } }
            end
            local body = { model = "m", messages = {{ role = "user", content = "hi" }} }
            local conf = { cache_key = { include_vars = { "http_x_tenant" } } }
            local p1 = key.partition(conf, ctx("acme"), body)
            local p2 = key.partition(conf, ctx("acme"), body)
            local p3 = key.partition(conf, ctx("globex"), body)
            ngx.say(p1 == p2 and "stable" or "unstable")
            ngx.say(p1 ~= p3 and "isolated" or "leaky")
        }
    }
--- response_body
stable
isolated



=== TEST 7: openai embeddings driver returns the vector from data[1].embedding
--- http_config
    server {
        listen 7737;
        default_type 'application/json';
        location /v1/embeddings {
            content_by_lua_block {
                ngx.say([[{"data":[{"embedding":[0.1,0.2,0.3]}]}]])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv = require("apisix.plugins.ai-cache.embeddings.openai")
            local vec, err = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:7737/v1/embeddings", model = "m", api_key = "k" },
                "hello world", http.new(), false)
            if not vec then ngx.say("err:", err); return end
            ngx.say(#vec, ":", vec[1], ",", vec[2], ",", vec[3])
        }
    }
--- response_body
3:0.1,0.2,0.3



=== TEST 8: openai embeddings driver fails closed on upstream non-2xx
--- http_config
    server {
        listen 7738;
        default_type 'application/json';
        location /v1/embeddings {
            content_by_lua_block { ngx.status = 500; ngx.say([[{"error":"boom"}]]) }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local drv = require("apisix.plugins.ai-cache.embeddings.openai")
            local vec, err = drv.get_embeddings(
                { endpoint = "http://127.0.0.1:7738/v1/embeddings", model = "m", api_key = "k" },
                "hi", http.new(), false)
            ngx.say(vec and "got-vec" or "nil-on-error")
        }
    }
--- response_body
nil-on-error
