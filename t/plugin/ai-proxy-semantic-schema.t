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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: valid semantic config is accepted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai",
                            "model": "text-embedding-3-small",
                            "auth": { "header": { "Authorization": "Bearer sk-emb" } }
                        },
                        "balancer": {
                            "algorithm": "semantic", "threshold": 0.75
                        },
                        "instances": [
                            {
                                "name": "code", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write a python function", "debug this code"],
                                "threshold": 0.85
                            },
                            {
                                "name": "default", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o-mini" },
                                "catchall": true
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: semantic requires examples on non-catchall instance
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai", "model": "text-embedding-3-small",
                            "auth": { "header": { "Authorization": "Bearer sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "code", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" }
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: examples



=== TEST 3: semantic requires embeddings config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "code", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: embeddings



=== TEST 4: at most one catchall instance
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai", "model": "text-embedding-3-small",
                            "auth": { "header": { "Authorization": "Bearer sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o-mini" },
                                "catchall": true
                            },
                            {
                                "name": "b", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "catchall": true
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: catchall



=== TEST 5: azure-openai embeddings require an endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "azure-openai", "model": "text-embedding-3-small",
                            "auth": { "header": { "api-key": "sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: endpoint



=== TEST 6: embeddings.model is required
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: model



=== TEST 7: catchall instance must not configure examples
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai", "model": "text-embedding-3-small",
                            "auth": { "header": { "Authorization": "Bearer sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            },
                            {
                                "name": "fallback", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o-mini" },
                                "catchall": true,
                                "examples": ["anything else"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: must not configure



=== TEST 8: azure-openai embeddings endpoint must include the deployment path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "azure-openai", "model": "text-embedding-3-small",
                            "endpoint": "https://my.openai.azure.com",
                            "auth": { "header": { "api-key": "sk-emb" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: full deployment path



=== TEST 9: embeddings.auth rejects ctx-dependent schemes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai", "model": "text-embedding-3-small",
                            "auth": { "gcp": { "service_account_json": "{}" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: gcp



=== TEST 10: embeddings.endpoint must carry a scheme and host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/anything",
                "plugins": {
                    "ai-proxy-multi": {
                        "embeddings": {
                            "provider": "openai", "model": "text-embedding-3-small",
                            "endpoint": "my.embeddings.host/v1/embeddings",
                            "auth": { "header": { "Authorization": "Bearer sk" } }
                        },
                        "balancer": { "algorithm": "semantic" },
                        "instances": [
                            {
                                "name": "a", "provider": "openai", "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer token" } },
                                "options": { "model": "gpt-4o" },
                                "examples": ["write code"]
                            }
                        ],
                        "ssl_verify": false
                    }
                }
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: invalid `embeddings.endpoint`
