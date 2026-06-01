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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: ai-proxy: encrypt auth.header (map of strings) and auth.gcp.service_account_json (3-level nested string)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer sk-test-key"
                                },
                                "query": {
                                    "api-key": "my-query-secret"
                                },
                                "gcp": {
                                    "service_account_json": "{\"type\":\"service_account\"}"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- admin API should return decrypted values
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local ai_proxy = res.value.plugins["ai-proxy"]
            ngx.say("header.Authorization: ", ai_proxy.auth.header.Authorization)
            ngx.say("query.api-key: ", ai_proxy.auth.query["api-key"])
            ngx.say("gcp.service_account_json: ", ai_proxy.auth.gcp.service_account_json)

            -- etcd should have encrypted values
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            local ai_proxy_etcd = res.body.node.value.plugins["ai-proxy"]
            ngx.say("etcd header encrypted: ",
                    ai_proxy_etcd.auth.header.Authorization ~= "Bearer sk-test-key")
            ngx.say("etcd query encrypted: ",
                    ai_proxy_etcd.auth.query["api-key"] ~= "my-query-secret")
            ngx.say("etcd gcp encrypted: ",
                    ai_proxy_etcd.auth.gcp.service_account_json ~= "{\"type\":\"service_account\"}")
        }
    }
--- response_body
header.Authorization: Bearer sk-test-key
query.api-key: my-query-secret
gcp.service_account_json: {"type":"service_account"}
etcd header encrypted: true
etcd query encrypted: true
etcd gcp encrypted: true



=== TEST 2: ai-proxy-multi: encrypt instances[].auth.header (array with nested map of strings)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "openai-1",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer sk-instance1-key"
                                        }
                                    }
                                },
                                {
                                    "name": "openai-2",
                                    "provider": "openai",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer sk-instance2-key"
                                        },
                                        "gcp": {
                                            "service_account_json": "{\"type\":\"service_account\",\"project_id\":\"test\"}"
                                        }
                                    }
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- admin API should return decrypted values
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local multi = res.value.plugins["ai-proxy-multi"]
            ngx.say("instance1 header: ", multi.instances[1].auth.header.Authorization)
            ngx.say("instance2 header: ", multi.instances[2].auth.header.Authorization)
            ngx.say("instance2 gcp: ", multi.instances[2].auth.gcp.service_account_json)

            -- etcd should have encrypted values
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            local multi_etcd = res.body.node.value.plugins["ai-proxy-multi"]
            ngx.say("etcd instance1 header encrypted: ",
                    multi_etcd.instances[1].auth.header.Authorization ~= "Bearer sk-instance1-key")
            ngx.say("etcd instance2 header encrypted: ",
                    multi_etcd.instances[2].auth.header.Authorization ~= "Bearer sk-instance2-key")
            ngx.say("etcd instance2 gcp encrypted: ",
                    multi_etcd.instances[2].auth.gcp.service_account_json ~=
                    "{\"type\":\"service_account\",\"project_id\":\"test\"}")
        }
    }
--- response_body
instance1 header: Bearer sk-instance1-key
instance2 header: Bearer sk-instance2-key
instance2 gcp: {"type":"service_account","project_id":"test"}
etcd instance1 header encrypted: true
etcd instance2 header encrypted: true
etcd instance2 gcp encrypted: true



=== TEST 3: ai-rag: encrypt deeply nested api_key fields (3-level dotted path)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "azure_openai": {
                                    "endpoint": "https://test.openai.azure.com/embeddings",
                                    "api_key": "embeddings-secret-key"
                                }
                            },
                            "vector_search_provider": {
                                "azure_ai_search": {
                                    "endpoint": "https://test.search.windows.net/indexes/idx/docs/search",
                                    "api_key": "search-secret-key"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- admin API should return decrypted values
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local ai_rag = res.value.plugins["ai-rag"]
            ngx.say("embeddings api_key: ",
                    ai_rag.embeddings_provider.azure_openai.api_key)
            ngx.say("search api_key: ",
                    ai_rag.vector_search_provider.azure_ai_search.api_key)

            -- etcd should have encrypted values
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            local ai_rag_etcd = res.body.node.value.plugins["ai-rag"]
            ngx.say("etcd embeddings encrypted: ",
                    ai_rag_etcd.embeddings_provider.azure_openai.api_key ~= "embeddings-secret-key")
            ngx.say("etcd search encrypted: ",
                    ai_rag_etcd.vector_search_provider.azure_ai_search.api_key ~= "search-secret-key")
        }
    }
--- response_body
embeddings api_key: embeddings-secret-key
search api_key: search-secret-key
etcd embeddings encrypted: true
etcd search encrypted: true



=== TEST 4: process_encrypt_field handles nil and missing fields gracefully
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            -- ai-proxy with no auth.gcp set: should not error
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer sk-only-header"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local ai_proxy = res.value.plugins["ai-proxy"]
            ngx.say("header.Authorization: ", ai_proxy.auth.header.Authorization)
            ngx.say("query is nil: ", ai_proxy.auth.query == nil)
            ngx.say("gcp is nil: ", ai_proxy.auth.gcp == nil)
        }
    }
--- response_body
header.Authorization: Bearer sk-only-header
query is nil: true
gcp is nil: true



=== TEST 5: regression: flat key encryption still works (basic-auth password)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "test_encrypt3",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- admin API returns decrypted
            local code, message, res = t('/apisix/admin/consumers/test_encrypt3',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res.value.plugins["basic-auth"].password)

            -- etcd stores encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/test_encrypt3'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password ~= "bar")
        }
    }
--- response_body
bar
true



=== TEST 6: regression: 2-level dotted path encryption still works (kafka-proxy sasl.password)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "kafka-proxy": {
                            "sasl": {
                                "username": "admin",
                                "password": "admin-secret"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res.value.plugins["kafka-proxy"].sasl.password)

            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["kafka-proxy"].sasl.password ~= "admin-secret")
        }
    }
--- response_body
admin-secret
true



=== TEST 7: encrypt_fields with array of strings leaf via process_encrypt_field
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            local ssl = require("apisix.ssl")

            -- Simulate array-of-strings encryption (e.g., secret_fallbacks)
            local conf = {
                secrets = {"secret-one", "secret-two", "secret-three"}
            }

            -- Encrypt
            plugin.process_encrypt_field(conf, "secrets", ssl.aes_encrypt_pkey, "test", "encrypt")

            -- Verify all elements are encrypted (not plaintext)
            for i, v in ipairs(conf.secrets) do
                ngx.say("encrypted[" .. i .. "] differs: ", v ~= "secret-" ..
                    (i == 1 and "one" or i == 2 and "two" or "three"))
            end

            -- Decrypt
            plugin.process_encrypt_field(conf, "secrets", ssl.aes_decrypt_pkey, "test", "decrypt")

            -- Verify all elements are restored
            ngx.say("decrypted[1]: ", conf.secrets[1])
            ngx.say("decrypted[2]: ", conf.secrets[2])
            ngx.say("decrypted[3]: ", conf.secrets[3])
        }
    }
--- response_body
encrypted[1] differs: true
encrypted[2] differs: true
encrypted[3] differs: true
decrypted[1]: secret-one
decrypted[2]: secret-two
decrypted[3]: secret-three
