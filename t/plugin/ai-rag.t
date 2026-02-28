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


my $resp_file = 't/assets/embeddings.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $embeddings = do { local $/; <$fh> };
close($fh);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 3623;

            default_type 'application/json';

            location /embeddings {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local req_headers = ngx.req.get_headers()
                    local auth = req_headers["Authorization"]

                    if auth ~= "Bearer correct-key" then
                        ngx.status = 401
                        ngx.say([[{"error": "Unauthorized"}]])
                        return
                    end

                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()
                    local data = json.decode(body)
                    -- Simple validation of body
                    if not data.input or not data.model then
                         ngx.status = 400
                         ngx.say([[{"error": "Bad Request"}]])
                         return
                    end

                    ngx.status = 200
                    ngx.say([[$embeddings]])
                }
            }

            location /indexes/rag-apisix/docs/search {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local req_headers = ngx.req.get_headers()
                    local key = req_headers["Api-Key"]

                    if key ~= "correct-key" then
                        ngx.status = 401
                        ngx.say([[{"error": "Unauthorized"}]])
                        return
                    end

                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()
                    local data = json.decode(body)
                    if not data.vectorQueries then
                         ngx.status = 400
                         ngx.say([[{"error": "Bad Request"}]])
                         return
                    end

                    -- Simulate Search: Return k docs
                    local all_docs = {
                        {
                            chunk = "Apache APISIX is a dynamic, real-time, high-performance API Gateway."
                        },
                        {
                            chunk = "It provides rich traffic management features like load balancing, dynamic upstream, canary release, circuit breaking, authentication, observability, and more."
                        },
                        {
                            chunk = "Apache Tomcat is an open source implementation of the Jakarta Servlet, Jakarta Server Pages, Jakarta Expression Language, Jakarta WebSocket, Jakarta Annotations and Jakarta Authentication specifications."
                        }
                    }

                    local docs = all_docs
                    -- The request body structure is:
                    -- {
                    --     "vectorQueries": [
                    --         {
                    --             "k": 10,
                    --             ...
                    --         }
                    --     ]
                    -- }
                    if data.vectorQueries and data.vectorQueries[1] and data.vectorQueries[1].k then
                        local k = tonumber(data.vectorQueries[1].k)
                        if k and k > 0 and k < #all_docs then
                            docs = {}
                            for i = 1, k do
                                table.insert(docs, all_docs[i])
                            end
                        end
                    end

                    ngx.status = 200
                    ngx.say(json.encode({ value = docs }))
                }
            }

            location /rerank {
                 content_by_lua_block {
                    local json = require("cjson.safe")
                    local req_headers = ngx.req.get_headers()
                    local auth = req_headers["Authorization"]

                    if auth ~= "Bearer correct-key" then
                        ngx.status = 401
                        ngx.say([[{"error": "Unauthorized"}]])
                        return
                    end

                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()
                    local data = json.decode(body)

                    if not data.query or not data.documents then
                         ngx.status = 400
                         ngx.say([[{"error": "Bad Request"}]])
                         return
                    end

                    -- Simulate Rerank: Prefer APISIX related docs (Index 0 and 1)
                    local all_results = {
                        {
                            index = 0,
                            relevance_score = 0.99
                        },
                        {
                            index = 1,
                            relevance_score = 0.95
                        },
                        {
                            index = 2,
                            relevance_score = 0.95
                        }
                    }

                    local results = all_results
                    if data.top_n then
                        local n = tonumber(data.top_n)
                        if n and n > 0 and n < #all_results then
                            results = {}
                            for i = 1, n do
                                table.insert(results, all_results[i])
                            end
                        end
                    end

                    ngx.status = 200
                    ngx.say(json.encode({ results = results }))
                 }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: Schema validation - missing embeddings_provider
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local ok, err = plugin.check_schema({
                vector_search_provider = {
                    ["azure-ai-search"] = {
                        endpoint = "http://127.0.0.1:3623/search",
                        api_key = "key",
                        fields = "text_vector",
                        select = "chunk"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "embeddings_provider" is required



=== TEST 2: Schema validation - missing vector_search_provider
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local ok, err = plugin.check_schema({
                embeddings_provider = {
                    openai = {
                        endpoint = "http://127.0.0.1:3623/embeddings",
                        api_key = "key"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "vector_search_provider" is required



=== TEST 3: Authentication validation - Wrong Embeddings Key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "openai": {
                                    "endpoint": "http://127.0.0.1:3623/embeddings",
                                    "api_key": "wrong-key"
                                }
                            },
                            "vector_search_provider": {
                                "azure-ai-search": {
                                    "endpoint": "http://127.0.0.1:3623/indexes/rag-apisix/docs/search",
                                    "api_key": "correct-key",
                                    "fields": "text_vector",
                                    "select": "chunk",
                                    "k": 10
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 4: Send request with wrong embeddings key
--- request
POST /echo
{
    "messages": [
        {
            "role": "user",
            "content": "What is Apache APISIX?"
        }
    ]
}
--- error_code: 401
--- response_body
{"error": "Unauthorized"}
--- error_log
could not get embeddings



=== TEST 5: Authentication validation - Wrong Search Key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "openai": {
                                    "endpoint": "http://127.0.0.1:3623/embeddings",
                                    "api_key": "correct-key"
                                }
                            },
                            "vector_search_provider": {
                                "azure-ai-search": {
                                    "endpoint": "http://127.0.0.1:3623/indexes/rag-apisix/docs/search",
                                    "api_key": "wrong-key",
                                    "fields": "text_vector",
                                    "select": "chunk",
                                    "k": 10
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 6: Send request with wrong search key
--- request
POST /echo
{
    "messages": [
        {
            "role": "user",
            "content": "What is Apache APISIX?"
        }
    ]
}
--- error_code: 401
--- response_body
{"error": "Unauthorized"}
--- error_log
could not get vector_search result



=== TEST 7: Happy Path (No Rerank) - Check Upstream Body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "openai": {
                                    "endpoint": "http://127.0.0.1:3623/embeddings",
                                    "api_key": "correct-key"
                                }
                            },
                            "vector_search_provider": {
                                "azure-ai-search": {
                                    "endpoint": "http://127.0.0.1:3623/indexes/rag-apisix/docs/search",
                                    "api_key": "correct-key",
                                    "fields": "text_vector",
                                    "select": "chunk",
                                    "k": 2
                                }
                            },
                            "rag_config":{
                                "input_strategy": "last"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 8: Verify Context Injection (No Rerank)
--- log_level: debug
--- request
POST /echo
{
    "messages": [
        {
            "role": "user",
            "content": "What is Apache APISIX?"
        }
    ]
}
--- error_log
Number of documents retrieved: 2
--- response_body eval
qr/Apache APISIX is a dynamic, real-time, high-performance API Gateway.*It provides rich traffic management features like load balancing.*What is Apache APISIX/



=== TEST 9: Happy Path (With Rerank)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "openai": {
                                    "endpoint": "http://127.0.0.1:3623/embeddings",
                                    "api_key": "correct-key"
                                }
                            },
                            "vector_search_provider": {
                                "azure-ai-search": {
                                    "endpoint": "http://127.0.0.1:3623/indexes/rag-apisix/docs/search",
                                    "api_key": "correct-key",
                                    "fields": "text_vector",
                                    "select": "chunk",
                                    "k": 10
                                }
                            },
                            "rerank_provider": {
                                "cohere": {
                                    "endpoint": "http://127.0.0.1:3623/rerank",
                                    "api_key": "correct-key",
                                    "model": "Cohere-rerank-v4.0-fast",
                                    "top_n": 1
                                }
                            },
                            "rag_config":{
                                "input_strategy": "all"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "scheme": "http",
                        "pass_host": "node"
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



=== TEST 10: Verify Context Injection (With Rerank)
--- log_level: debug
--- request
POST /echo
{
    "messages": [
        {
            "role": "user",
            "content": "What is Apache APISIX?"
        }
    ]
}
--- error_log
Number of documents retrieved: 1
--- response_body eval
qr/Apache APISIX is a dynamic, real-time, high-performance API Gateway.*What is Apache APISIX/
