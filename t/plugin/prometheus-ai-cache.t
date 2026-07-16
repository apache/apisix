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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
plugin_attr:
    prometheus:
        refresh_interval: 0.1
plugins:
  - ai-proxy
  - ai-cache
  - prometheus
  - public-api
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $http_config = <<_EOC_;
    server {
        listen 6724;
        default_type 'application/json';

        location /v1/embeddings {
            content_by_lua_block { require("lib.ai_cache_mock").embeddings() }
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: create a route with ai-proxy, ai-cache and the metrics public-api route
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)

            local data = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "uri": "/chat",
                        "name": "ai-cache-route",
                        "plugins": {
                            "prometheus": {},
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
                                "bypass_on": [{"header": "X-No-Cache", "equals": "1"}],
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
                    }]],
                },
                {
                    url = "/apisix/admin/routes/metrics",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/prometheus/metrics"
                    }]]
                },
            }

            local t = require("lib.test_admin").test

            for _, d in ipairs(data) do
                local code, body = t(d.url, ngx.HTTP_PUT, d.data)
                if code >= 300 then ngx.status = code end
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 2



=== TEST 2: send a chat request (cache MISS)
--- request
POST /chat
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- error_code: 200
--- wait: 0.5



=== TEST 3: assert ai_cache_misses_total metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_misses_total\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model="gpt-4o"\} 1/



=== TEST 4: send the same chat request (exact-layer HIT)
--- request
POST /chat
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- response_headers
X-AI-Cache-Status: HIT
! X-AI-Cache-Similarity
--- error_code: 200
--- wait: 0.3



=== TEST 5: assert ai_cache_hits_total metric with layer=exact and empty llm_model
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_hits_total\{layer="exact",route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model=""\} 1/



=== TEST 6: ai_cache_embedding_latency is not recorded for the exact hit
--- request
GET /apisix/prometheus/metrics
--- response_body_unlike eval
qr/apisix_ai_cache_embedding_latency_count\{[^}]*llm_model=""\}/



=== TEST 7: send a paraphrased chat request (semantic-layer HIT, cos 0.922 >= 0.9)
--- request
POST /chat
{"model":"gpt-4o","messages":[{"role":"user","content":"What's the capital city of France?"}]}
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d
--- error_code: 200
--- wait: 0.3



=== TEST 8: assert ai_cache_hits_total metric with layer=semantic
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_hits_total\{layer="semantic",route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model=""\} 1/



=== TEST 9: assert ai_cache_embedding_latency_bucket metric for the miss lookup
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_embedding_latency_bucket\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model="gpt-4o",le="\d+"\} 1/



=== TEST 10: assert ai_cache_embedding_latency_count metric for the miss lookup
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_embedding_latency_count\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model="gpt-4o"\} 1/



=== TEST 11: assert ai_cache_embedding_latency_sum metric for the miss lookup
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_embedding_latency_sum\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model="gpt-4o"\} \d+/



=== TEST 12: assert ai_cache_embedding_latency_count metric for the semantic-hit lookup
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_embedding_latency_count\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model=""\} 1/



=== TEST 13: send a chat request with the bypass header (BYPASS)
--- request
POST /chat
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-No-Cache: 1
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: BYPASS
--- error_code: 200
--- wait: 0.3



=== TEST 14: assert ai_cache_bypasses_total metric
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_ai_cache_bypasses_total\{route="ai-cache-route",route_id="1",.*node="ai-proxy-openai",request_type="ai_chat",request_llm_model="gpt-4o",llm_model="gpt-4o"\} 1/



=== TEST 15: reject disabling the structural `layer` label on ai_cache_hits_total
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/prometheus',
                ngx.HTTP_PUT,
                [[{"disabled_labels": {"ai_cache_hits_total": ["layer"]}}]])
            ngx.say(body)
        }
    }
--- response_body eval
qr/failed to validate item 1/
