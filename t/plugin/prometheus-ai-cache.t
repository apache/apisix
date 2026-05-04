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

    my $user_yaml_config = <<_EOC_;
plugin_attr:
    prometheus:
        refresh_interval: 0.1
plugins:
  - ai-proxy
  - ai-cache
  - prometheus
  - public-api
  - key-auth
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

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

    location /v1/embeddings-fail {
        content_by_lua_block {
            ngx.status = 500
            ngx.say('{"error":"simulated embedding failure"}')
        }
    }
}
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: set up routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local routes = {
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "uri": "/exact",
                        "plugins": {
                            "prometheus": {},
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
                    }]],
                },
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "uri": "/semantic",
                        "plugins": {
                            "prometheus": {},
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
                                "exact": { "ttl": 60 },
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
                    }]],
                },
                {
                    url = "/apisix/admin/routes/3",
                    data = [[{
                        "uri": "/semantic-fail",
                        "plugins": {
                            "prometheus": {},
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
                                "layers": ["semantic"],
                                "semantic": {
                                    "similarity_threshold": 0.90,
                                    "ttl": 300,
                                    "embedding": {
                                        "provider": "openai",
                                        "endpoint": "http://127.0.0.1:1990/v1/embeddings-fail",
                                        "api_key": "test-key"
                                    }
                                },
                                "redis_host": "127.0.0.1"
                            }
                        }
                    }]],
                },
                {
                    url = "/apisix/admin/routes/4",
                    data = [[{
                        "uri": "/exact-auth",
                        "plugins": {
                            "prometheus": {},
                            "key-auth": {},
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
                    }]],
                },
                {
                    url = "/apisix/admin/consumers",
                    data = [[{
                        "username": "alice",
                        "plugins": {
                            "key-auth": {
                                "key": "alice-key"
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
                    }]],
                },
            }

            for _, route in ipairs(routes) do
                local code, body = t(route.url, ngx.HTTP_PUT, route.data)
                if code >= 300 then
                    ngx.status = code
                end
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 6



=== TEST 2: MISS request - upstream called
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the meaning of life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 3: same request - HIT-L1
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the meaning of life?"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- wait: 1



=== TEST 4: verify miss counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_misses_total\{route_id="1",service_id="",consumer=""\} 1/



=== TEST 5: verify hit counter with layer label
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_hits_total\{route_id="1",service_id="",consumer="",layer="l1"\} 1/



=== TEST 6: BYPASS request - upstream called, no cache interaction
--- request
POST /exact
{"messages":[{"role":"user","content":"What is the meaning of life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-Cache-Bypass: 1
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 7: verify BYPASS did not increment misses counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_misses_total\{route_id="1",service_id="",consumer=""\} 1\n/



=== TEST 8: verify BYPASS did not increment hits counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_hits_total\{route_id="1",service_id="",consumer="",layer="l1"\} 1\n/



=== TEST 9: cleanup Redis cache state before semantic tests
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



=== TEST 10: L2 first request - MISS, embedding API called
--- request
POST /semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 11: L2 second request - different wording, HIT-L2
--- request
POST /semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L2
--- wait: 1



=== TEST 12: verify miss counter for semantic route (route_id=2)
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_misses_total\{route_id="2",service_id="",consumer=""\} 1/



=== TEST 13: verify hits counter with layer="l2"
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_hits_total\{route_id="2",service_id="",consumer="",layer="l2"\} 1/



=== TEST 14: verify embedding latency histogram with provider label
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_embedding_latency_count\{route_id="2",service_id="",consumer="",provider="openai"\} 2/



=== TEST 15: embedding failure - request still returns 200 via fallback
--- request
POST /semantic-fail
{"messages":[{"role":"user","content":"What does this fail at?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 16: verify embedding_failures counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_embedding_failures_total\{route_id="3",service_id="",consumer=""\} 1/



=== TEST 17: verify embedding-failure request also counted as miss
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_misses_total\{route_id="3",service_id="",consumer=""\} 1/



=== TEST 18: authenticated MISS request - consumer alice
--- request
POST /exact-auth
{"messages":[{"role":"user","content":"Authenticated cache test"}]}
--- more_headers
Content-Type: application/json
apikey: alice-key
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 19: authenticated HIT-L1 request - consumer alice
--- request
POST /exact-auth
{"messages":[{"role":"user","content":"Authenticated cache test"}]}
--- more_headers
Content-Type: application/json
apikey: alice-key
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- wait: 1



=== TEST 20: verify consumer label is populated on hits counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_hits_total\{route_id="4",service_id="",consumer="alice",layer="l1"\} 1/



=== TEST 21: verify consumer label is populated on misses counter
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_ai_cache_misses_total\{route_id="4",service_id="",consumer="alice"\} 1/



=== TEST 22: verify cache hit is labelled as ai_chat (not traditional_http)
--- request
GET /apisix/prometheus/metrics
--- response_body_like eval
qr/apisix_http_status\{code="200",route="1"[^}]*request_type="ai_chat"[^}]*response_source="apisix"[^}]*\} 1/
