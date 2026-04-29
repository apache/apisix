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
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed



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
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed



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
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed



=== TEST 7: set up route for L1 cache tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/chat",
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



=== TEST 8: first request - cache MISS, upstream called
--- request
POST /chat
{"messages":[{"role":"user","content":"What is the answer to life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/content/



=== TEST 9: second identical request - cache HIT-L1, no upstream call
--- request
POST /chat
{"messages":[{"role":"user","content":"What is the answer to life?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- response_body_like eval
qr/content/
--- error_log
ai-cache: L1 hit for key



=== TEST 10: bypass header - BYPASS, upstream called, not cached
--- request
POST /chat
{"messages":[{"role":"user","content":"What is the bypass question?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-Cache-Bypass: 1
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS



=== TEST 11: same prompt without bypass after bypass - still MISS (bypass did not cache)
--- request
POST /chat
{"messages":[{"role":"user","content":"What is the bypass question?"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 12: set up route for 4xx test
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



=== TEST 13: 4xx from upstream - not cached
--- request
POST /error
{"messages":[{"role":"user","content":"trigger an error please"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 400
--- error_code: 400
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 14: same prompt after 4xx - still MISS (4xx was not cached)
--- request
POST /error
{"messages":[{"role":"user","content":"trigger an error please"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 400
--- error_code: 400
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 15: openai driver - parses embedding vector correctly
--- http_config
server {
    listen 1990;
    default_type 'application/json';

    location /v1/embeddings {
        content_by_lua_block {
            local cjson = require("cjson.safe")
            ngx.req.read_body()
            local body = cjson.decode(ngx.req.get_body_data())

            if ngx.req.get_headers()["Authorization"] ~= "Bearer test-key" then
                ngx.status = 401
                ngx.say('{"error":"unauthorized"}')
                return
            end

            ngx.status = 200
            ngx.say(cjson.encode({
                data = {
                    { embedding = {0.1, 0.2, 0.3}, index = 0, object = "embedding" }
                },
                model = body.model,
                object = "list"
            }))
        }
    }
}
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local driver = require("apisix.plugins.ai-cache.embeddings.openai")

            local httpc = http.new()
            local conf = {
                endpoint = "http://127.0.0.1:1990/v1/embeddings",
                api_key = "test-key",
                model = "text-embedding-3-small",
            }

            local embedding, status, err = driver.get_embeddings(conf, "hello world", httpc, false)
            if not embedding then
                ngx.say("error: ", err)
                return
            end

            if #embedding ~= 3 then
                ngx.say("wrong length: ", #embedding)
                return
            end

            ngx.say("ok: ", embedding[1], " ", embedding[2], " ", embedding[3])
        }
    }
--- response_body
ok: 0.1 0.2 0.3



=== TEST 16: openai driver - 429 from API return nil with status
--- http_config
server {
    listen 1990;
    default_type 'application/json';

    location /v1/embeddings {
        content_by_lua_block {
            ngx.status = 429
            ngx.say('{"error":{"message":"rate limit exceeded","type":"requests"}}')
        }
    }
}
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local driver = require("apisix.plugins.ai-cache.embeddings.openai")

            local httpc = http.new()
            local conf = {
                endpoint = "http://127.0.0.1:1990/v1/embeddings",
                api_key = "test-key",
            }

            local embedding, status, err = driver.get_embeddings(conf, "hello", httpc, false)
            if embedding then
                ngx.say("unexpected success")
                return
            end

            ngx.say("status: ", status)
        }
    }
--- response_body
status: 429



=== TEST 17: azure_openai driver - parses embedding vector correctly
--- http_config
server {
    listen 1990;
    default_type 'application/json';

    location /embeddings {
        content_by_lua_block {
            local cjson = require("cjson.safe")

            if ngx.req.get_headers()["api-key"] ~= "azure-test-key" then
                ngx.status = 401
                ngx.say('{"error":"unauthorized"}')
                return
            end

            ngx.status = 200
            ngx.say(cjson.encode({
                data = {
                    { embedding = {0.4, 0.5, 0.6}, index = 0, object = "embedding" }
                },
                object = "list"
            }))
        }
    }
}
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local driver = require("apisix.plugins.ai-cache.embeddings.azure_openai")

            local httpc = http.new()
            local conf = {
                endpoint = "http://127.0.0.1:1990/embeddings",
                api_key = "azure-test-key",
            }

            local embedding, status, err = driver.get_embeddings(conf, "hello world", httpc, false)
            if not embedding then
                ngx.say("error: ", err)
                return
            end

            ngx.say("ok: ", embedding[1], " ", embedding[2], " ", embedding[3])
        }
    }
--- response_body
ok: 0.4 0.5 0.6



=== TEST 18: openai driver - 500 from API returns nil with status
--- http_config
server {
    listen 1990;
    default_type 'application/json';

    location /v1/embeddings {
        content_by_lua_block {
            ngx.status = 500
            ngx.say('{"error":{"message":"internal server error"}}')
        }
    }
}
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local driver = require("apisix.plugins.ai-cache.embeddings.openai")

            local httpc = http.new()
            local conf = {
                endpoint = "http://127.0.0.1:1990/v1/embeddings",
                api_key = "test-key",
            }

            local embedding, status, err = driver.get_embeddings(conf, "hello", httpc, false)
            if embedding then
                ngx.say("unexpected success")
                return
            end

            ngx.say("status: ", status)
        }
    }
--- response_body
status: 500



=== TEST 19: clean up L2 state before semantic tests
--- config
    location /t {
        content_by_lua_block {
            local redis = require("resty.redis")
            local red = redis:new()
            red:set_timeout(1000)
            assert(red:connect("127.0.0.1", 6379))

            red["FT.DROPINDEX"](red, "ai-cache-idx", "DD")

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



=== TEST 20: set up route for L2 semantic cache tests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
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



=== TEST 21: L2 - first request, cache MISS, stored in L2
--- request
POST /semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 22: L2 - different wording hits L2 (same vector from fixture)
--- request
POST /semantic
{"messages":[{"role":"user","content":"Name the capital city of France"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L2
--- response_body_like eval
qr/content/
--- error_log
ai-cache: L2 hit



=== TEST 23: L2 - original prompt now hits L1 (backfilled by the L2 hit)
--- request
POST /semantic
{"messages":[{"role":"user","content":"What is the capital of France??"}]}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
--- error_log
ai-cache: L1 hit for key



=== TEST 24: L2 degradation - search error results in MISS, not 500
--- config
    location /t {
        content_by_lua_block {
            local semantic = require("apisix.plugins.ai-cache.semantic")
            local conf = {
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_timeout = 100,
            }

            local text, sim, err = semantic.search(conf, "", {0.1, 0.2, 0.3}, 0.95)
            if err then
                ngx.say("degraded gracefully")
            else
                ngx.say("miss, no error")
            end
        }
    }
--- response_body_like eval
qr/degraded gracefully|miss, no error/



=== TEST 25: streaming MISS - upstream called, response cached via log phase
--- request
POST /chat
{"messages":[{"role":"user","content":"Stream me something cool"}],"stream":true}
--- more_headers
Content-Type: application/json
X-AI-Fixture: openai/chat-streaming.sse
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS



=== TEST 26: streaming HIT - Content-Type is text/event-stream, SSE body returned
--- request
POST /chat
{"messages":[{"role":"user","content":"Stream me something cool"}],"stream":true}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
Content-Type: text/event-stream
--- response_body_like eval
qr/data:.*content/
--- wait: 1



=== TEST 27: non-streaming HIT after streaming MISS - returns JSON
--- request
POST /chat
{"messages":[{"role":"user","content":"Stream me something cool"}]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-AI-Cache-Status: HIT-L1
Content-Type: application/json
--- response_body_like eval
qr/content/
