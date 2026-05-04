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

=== TEST 1: set up route with cache_key include_vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/scoped",
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
                            "cache_key": {
                                "include_vars": ["$http_x_tenant_id"]
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



=== TEST 2: tenant-a first request - MISS
--- request
POST /scoped
{"messages":[{"role":"user","content":"scope test prompt"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-a
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 3: tenant-b same prompt - MISS (proves cache_key partitioning)
--- request
POST /scoped
{"messages":[{"role":"user","content":"scope test prompt"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-b
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 4: tenant-a same prompt again - HIT-L1
--- request
POST /scoped
{"messages":[{"role":"user","content":"scope test prompt"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-a
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1



=== TEST 5: set up consumers for include_consumer test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local consumers = {
                { username = "alice", key = "alice-key" },
                { username = "bob",   key = "bob-key"   },
            }

            for _, c in ipairs(consumers) do
                local code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    string.format([[{
                        "username": "%s",
                        "plugins": { "key-auth": { "key": "%s" } }
                    }]], c.username, c.key)
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 6: set up route with cache_key include_consumer + key-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/per-consumer",
                    "plugins": {
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
                            "cache_key": {
                                "include_consumer": true
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



=== TEST 7: alice first request - MISS
--- request
POST /per-consumer
{"messages":[{"role":"user","content":"per-consumer prompt"}]}
--- more_headers
Content-Type: application/json
apikey: alice-key
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 8: bob same prompt - MISS (proves include_consumer partitioning)
--- request
POST /per-consumer
{"messages":[{"role":"user","content":"per-consumer prompt"}]}
--- more_headers
Content-Type: application/json
apikey: bob-key
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 9: bob same prompt again - HIT-L1 (proves bob has own cache)
--- request
POST /per-consumer
{"messages":[{"role":"user","content":"per-consumer prompt"}]}
--- more_headers
Content-Type: application/json
apikey: bob-key
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1



=== TEST 10: set up route with L2 semantic + cache_key include_vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/scoped-semantic",
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
                            "cache_key": {
                                "include_vars": ["$http_x_tenant_id"]
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



=== TEST 11: tenant-a first request - MISS, writes to L2 with scope=hash(tenant-a)
--- request
POST /scoped-semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-a
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 12: tenant-b same prompt - MISS (FT.SEARCH scope filter excludes tenant-a's entry)
--- request
POST /scoped-semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-b
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- wait: 1



=== TEST 13: tenant-a paraphrase - HIT-L2 (scope filter finds tenant-a's entry)
--- request
POST /scoped-semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-a
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L2



=== TEST 14: tenant-b paraphrase - HIT-L2 (proves tenant-b has own L2 entry)
--- request
POST /scoped-semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-Tenant-Id: tenant-b
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L2
