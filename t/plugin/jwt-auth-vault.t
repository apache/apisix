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

    my $vault_config = $block->extra_yaml_config // <<_EOC_;
vault:
  host: "http://0.0.0.0:8200"
  timeout: 10
  prefix: kv/apisix
  token: root
_EOC_

    $block->set_value("extra_yaml_config", $vault_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwt-auth")
            local core = require("apisix.core")
            for _, conf in ipairs({
                {
                    -- public and private key are not provided for RS256, returns error
                    key = "key-1",
                    algorithm = "RS256"
                },
                {
                    -- public and private key are not provided but vault config is enabled.
                    key = "key-1",
                    algorithm = "RS256",
                    vault = {}
                }
            }) do
                local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("ok")
                end
            end
        }
    }
--- response_body
failed to validate dependent schema for "algorithm": value should match only one schema, but matches none
ok



=== TEST 2: create a consumer with plugin and username
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
                            "key": "key-hs256",
                            "algorithm": "HS256",
                            "vault":{}
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



=== TEST 3: enable jwt auth plugin using admin api
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



=== TEST 4: create public API route (jwt-auth sign)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/jwt/sign"
                 }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: sign a jwt and access/verify /secure-endpoint, fails as no secret entry into vault
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=key-hs256',
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(res)
        }
    }
--- response_body
failed to sign jwt
--- error_code: 503
--- error_log eval
qr/failed to sign jwt, err: secret could not found in vault/
--- grep_error_log_out
failed to sign jwt, err: secret could not found in vault



=== TEST 6: store HS256 secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/consumer/jack/jwt-auth secret=$3nsitiv3-c8d3
--- response_body
Success! Data written to: kv/apisix/consumer/jack/jwt-auth



=== TEST 7: sign a HS256 jwt and access/verify /secure-endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=key-hs256',
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(res)
        }
    }
--- response_body
successfully invoked secure endpoint



=== TEST 8: store rsa key pairs into vault from local filesystem
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/consumer/jim/jwt-auth public_key=@t/certs/public.pem private_key=@t/certs/private.pem
--- response_body
Success! Data written to: kv/apisix/consumer/jim/jwt-auth



=== TEST 9: create consumer for RS256 algorithm with key pair fetched from vault
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jim",
                    "plugins": {
                        "jwt-auth": {
                            "key": "rsa",
                            "algorithm": "RS256",
                            "vault":{}
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



=== TEST 10: sign a jwt with with rsa key pair and access /secure-endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=rsa',
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(res)
        }
    }
--- response_body
successfully invoked secure endpoint



=== TEST 11: store rsa private key into vault from local filesystem
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/consumer/john/jwt-auth private_key=@t/certs/private.pem
--- response_body
Success! Data written to: kv/apisix/consumer/john/jwt-auth



=== TEST 12: create consumer for RS256 algorithm with private key fetched from vault and public key in consumer schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "john",
                    "plugins": {
                        "jwt-auth": {
                            "key": "rsa1",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA79XYBopfnVMKxI533oU2\nVFQbEdSPtWRD+xSl73lHLVboGP1lSIZtnEj5AcTN2uDW6AYPiWL2iA3lEEsDTs7J\nBUXyl6pysBPfrqC8n/MOXKaD4e8U5GAHFiwHWg2WzHlfFSlFkLjzp0vPkDK+fQ4C\nlrd7shAyitB7use6DHcVCKuI4bFOoFbdI5sBGeyoD833g+ql9bRkH/vf8O+rPwHA\nM+47r1iv3lY3ex0P45PRd7U7rq8P8UIw6qOI1tiYuKlFJmjFdcwtYG0dctxWwgL1\n+7njrVQoWvuOTSsc9TDMhZkmmSsU3wXjaPxJpydck1C/w9ZLqsctKK5swYWhIcbc\nBQIDAQAB\n-----END PUBLIC KEY-----\n",
                            "vault":{}
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



=== TEST 13: sign a jwt with with rsa key pair and access /secure-endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=rsa1',
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
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(res)
        }
    }
--- response_body
successfully invoked secure endpoint
