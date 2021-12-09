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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8777;

        location /secure-endpoint {
            content_by_lua_block {
                ngx.say("successfully invoked secure endpoint")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema - if public and private key are not provided for RS256
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {
                key = "key-1",
                algorithm = "RS256"
            }

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
failed to validate dependent schema for "algorithm": value should match only one schema, but matches none



=== TEST 2: schema - vault config enabled, but vault path doesn't contains secret.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {
                key = "key-1",
                algorithm = "RS256",
                vault = {}
            }

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
missing valid public key



=== TEST 3: store rsa key pair into vault kv/apisix/rsa/key1
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/rsa/key1 private_key=prikey public_key=pubkey
--- response_body
Success! Data written to: kv/apisix/rsa/key1



=== TEST 4: keypair fetched from vault
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {
                key = "key-1",
                algorithm = "RS256",
                vault = {
                    path = "kv/apisix/rsa/key1",
                    add_prefix = false
                }
            }

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 5: store only private key into vault kv/apisix/rsa/key2
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/rsa/key2 private_key=prikey
--- response_body
Success! Data written to: kv/apisix/rsa/key2



=== TEST 6: private key fetched from vault and public key from config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {
                key = "key-1",
                algorithm = "RS256",
                public_key = "pubkey",
                vault = {
                    path = "kv/apisix/rsa/key1",
                    add_prefix = false
                }
            }

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 7: preparing test 7, deleting any kv stored into path kv/apisix/jwt-auth/key/key-hs256
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv delete kv/apisix/jwt-auth/key/key-hs256
--- response_body
Success! Data deleted (if it existed) at: kv/apisix/jwt-auth/key/key-hs256



=== TEST 8: HS256, generate and store key into vault
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            local conf = {
                key = "key-hs256",
                algorithm = "HS256",
                vault = {
                }
            }

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            else
                ngx.say("vault-path: ", conf.vault.path)
                ngx.say("redacted-secret: ", conf.secret)
            end
        }
    }
--- response_body
vault-path: jwt-auth/key/key-hs256
redacted-secret: <vault: jwt-auth/key/key-hs256>



=== TEST 9: check generated key from test 8 - hs256 self generated kv path for vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv get kv/apisix/jwt-auth/key/key-hs256
--- response_body eval
qr/===== Data =====
Key       Value
---       -----
secret    [a-zA-Z0-9+\\\/]+={0,2}/



=== TEST 10: store a secret for creating a consumer into some random path
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/some/random/path secret=apisix
--- response_body
Success! Data written to: kv/some/random/path



=== TEST 11: create a consumer with plugin and username
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-vault",
                            "algorithm": "HS256",
                            "vault":{
                                "path": "kv/some/random/path",
                                "add_prefix": false
                            }
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "jwt-auth": {
                                    "key": "user-key-vault",
                                    "algorithm": "HS256",
                                    "vault":{
                                        "path": "kv/some/random/path",
                                        "add_prefix": false
                                    }
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: enable jwt auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8777": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/secure-endpoint"
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



=== TEST 13: sign a jwt and access/verify /secure-endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=user-key-vault',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end
            
            local code, _, res = t('/secure-endpoint?jwt=' .. sign,
                ngx.HTTP_GET
            )
            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
successfully invoked secure endpoint



=== TEST 14: store rsa key pairs into vault from local filesystem
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/rsa/keypair1 public_key=@t/certs/public.pem private_key=@t/certs/private.pem
--- response_body
Success! Data written to: kv/rsa/keypair1



=== TEST 15 create consumer for RS256 algorithm with keypair fetched from vault
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "rsa-keypair-vault",
                            "algorithm": "RS256",
                            "vault":{
                                "path": "kv/rsa/keypair1",
                                "add_prefix": false
                            }
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: sign a jwt with with rsa keypair and access /secure-endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=rsa-keypair-vault',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end
            
            local code, _, res = t('/secure-endpoint?jwt=' .. sign,
                ngx.HTTP_GET
            )
            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
successfully invoked secure endpoint

