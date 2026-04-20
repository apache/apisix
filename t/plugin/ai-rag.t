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


my $resp_file = 't/assets/embeddings.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $embeddings = do { local $/; <$fh> };
close($fh);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $main_config = $block->main_config // <<_EOC_;
        env AI_RAG_APIKEY=apikey;
_EOC_

    $block->set_value("main_config", $main_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 3623;

            default_type 'application/json';

            location /embeddings {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                        return
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local header_auth = ngx.req.get_headers()["api-key"]

                    if header_auth ~= "key" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.status = 200
                    ngx.say([[$embeddings]])
                }
            }

            location /search {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end

                    local header_auth = ngx.req.get_headers()["api-key"]
                    if header_auth ~= "key" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)
                    if body.vectorQueries[1].vector[1] ~= 123456789 then
                        ngx.status = 500
                        ngx.say({ error = "occurred" })
                        return
                    end

                    ngx.status = 200
                    ngx.print("passed")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: minimal viable configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local ok, err = plugin.check_schema({
                embeddings_provider = {
                    azure_openai = {
                        api_key = "sdfjasdfh",
                        endpoint = "http://a.b.com"
                    }
                },
                vector_search_provider = {
                    azure_ai_search = {
                        api_key = "iuhsdf",
                        endpoint = "http://a.b.com"
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
passed



=== TEST 2: vector search provider missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local ok, err = plugin.check_schema({
                embeddings_provider = {
                    azure_openai = {
                        api_key = "sdfjasdfh",
                        endpoint = "http://a.b.com"
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



=== TEST 3: embeddings provider missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local ok, err = plugin.check_schema({
                vector_search_provider = {
                    azure_ai_search = {
                        api_key = "iuhsdf",
                        endpoint = "http://a.b.com"
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



=== TEST 4: wrong auth header for embeddings provider
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
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "wrongkey"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "key"
                                }
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



=== TEST 5: send request
--- request
POST /echo
{"ai_rag":{"vector_search":{"fields":"contentVector"},"embeddings":{"input":"which service is good for devops","dimensions":1024}}}
--- error_code: 401
--- response_body
Unauthorized
--- error_log
could not get embeddings: Unauthorized



=== TEST 6: wrong auth header for search provider
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
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "key"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "wrongkey"
                                }
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



=== TEST 7: send request
--- request
POST /echo
{"ai_rag":{"vector_search":{"fields":"contentVector"},"embeddings":{"input":"which service is good for devops","dimensions":1024}}}
--- error_code: 401
--- error_log
could not get vector_search result: Unauthorized



=== TEST 8: send request with empty body
--- request
POST /echo
--- error_code: 400
--- response_body_chomp
failed to get request body: request body is empty



=== TEST 9: send request with vector search fields missing
--- request
POST /echo
{"ai_rag":{"vector_search":{"missing-fields":"something"},"embeddings":{"input":"which service is good for devops","dimensions":1024}}}
--- error_code: 400
--- error_log
request body fails schema check: property "ai_rag" validation failed: property "vector_search" validation failed: property "fields" is required



=== TEST 10: send request with embedding input missing
--- request
POST /echo
{"ai_rag":{"vector_search":{"fields":"something"},"embeddings":{"missinginput":"which service is good for devops"}}}
--- error_code: 400
--- error_log
request body fails schema check: property "ai_rag" validation failed: property "embeddings" validation failed: property "input" is required



=== TEST 11: configure plugin with right auth headers
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
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "key"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "key"
                                }
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



=== TEST 12: send request with embedding input missing
--- request
POST /echo
{"ai_rag":{"vector_search":{"fields":"something"},"embeddings":{"input":"which service is good for devops"}}}
--- error_code: 200
--- response_body eval
qr/\{"messages":\[\{"content":"passed","role":"user"\}\]\}|\{"messages":\[\{"role":"user","content":"passed"\}\]\}/



=== TEST 13: configure route for Responses API RAG injection test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uris": ["/echo", "/v1/responses"],
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "key"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "key"
                                }
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



=== TEST 14: Responses API RAG injection - RAG result appended to input
--- request
POST /v1/responses
{"input":"which service is good for devops","ai_rag":{"vector_search":{"fields":"something"},"embeddings":{"input":"which service is good for devops"}}}
--- error_code: 200
--- response_body eval
qr/"input":"which service is good for devops\\npassed"/



=== TEST 15: ssl_verify defaults to true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local conf = {
                embeddings_provider = {
                    azure_openai = {
                        api_key = "key",
                        endpoint = "http://a.b.com"
                    }
                },
                vector_search_provider = {
                    azure_ai_search = {
                        api_key = "key",
                        endpoint = "http://a.b.com"
                    }
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.ssl_verify)
        }
    }
--- response_body
true
--- no_error_log
[error]



=== TEST 16: ssl_verify can be set to false
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local conf = {
                ssl_verify = false,
                embeddings_provider = {
                    azure_openai = {
                        api_key = "key",
                        endpoint = "http://a.b.com"
                    }
                },
                vector_search_provider = {
                    azure_ai_search = {
                        api_key = "key",
                        endpoint = "http://a.b.com"
                    }
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.ssl_verify)
        }
    }
--- response_body
false
--- no_error_log
[error]



=== TEST 17: ssl_verify=false is passed through to resty.http request_uri
--- extra_init_by_lua
    local http = require("resty.http")
    local old_new = http.new
    http.new = function(self)
        local instance = old_new(self)
        local old_request_uri = instance.request_uri
        instance.request_uri = function(self, uri, opts)
            if opts then
                ngx.log(ngx.INFO, "ai_rag ssl_verify: ", tostring(opts.ssl_verify))
            end
            return old_request_uri(self, uri, opts)
        end
        return instance
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uris": ["/echo"],
                    "plugins": {
                        "ai-rag": {
                            "ssl_verify": false,
                            "embeddings_provider": {
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "key"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "key"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {"127.0.0.1:1980": 1},
                        "scheme": "http"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- send a real request to trigger both embeddings and vector-search HTTP calls
            local http_client = require("resty.http")
            local httpc = http_client.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/echo", {
                method = "POST",
                headers = {["Content-Type"] = "application/json"},
                body = [[{"ai_rag":{"vector_search":{"fields":"something"},"embeddings":{"input":"test"}}}]],
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
ai_rag ssl_verify: false



=== TEST 18: configure plugin with api_key via nginx env directive secret reference
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
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "$ENV://AI_RAG_APIKEY"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "http://localhost:3623/search",
                                    "api_key": "$ENV://AI_RAG_APIKEY"
                                }
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
