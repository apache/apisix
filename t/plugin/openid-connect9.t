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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

BEGIN {
    $ENV{CLIENT_SECRET_ENV} = "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa";
    $ENV{VAULT_TOKEN} = "root";
}

run_tests();

__DATA__

=== TEST 1: configure oidc plugin with small public key using environment variable
    --- config
        location /t {
            content_by_lua_block {
                local t = require("lib.test_admin").test
                    local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{ "plugins": {
                    "openid-connect": {
                        "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                            "client_secret": "$ENV://CLIENT_SECRET_ENV",
                            "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                            "redirect_uri": "https://iresty.com",
                            "ssl_verify": false,
                            "timeout": 10,
                            "bearer_only": true,
                            "scope": "apisix",
                            "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                            "token_signing_alg_values_expected": "RS256"
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
                    end
                        ngx.say(body)
        }
}
--- response_body
passed



=== TEST 2: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo client_secret=60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa
--- response_body
Success! Data written to: kv/apisix/foo



=== TEST 3: configure oidc plugin with small public key using vault
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "$secret://vault/test1/foo/client_secret",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
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
            end
            ngx.say(body)
}
}
--- response_body
passed



=== TEST 4: configure oidc plugin with small public key using vault and request with token should success
--- config
    location /hello {
        content_by_lua_block {
            ngx.say("success")
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                            "client_secret": "$secret://vault/test1/foo/client_secret",
                            "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                            "redirect_uri": "https://iresty.com",
                            "ssl_verify": false,
                            "timeout": 10,
                            "bearer_only": true,
                            "scope": "apisix",
                            "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                            [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                            [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                            [[-----END PUBLIC KEY-----",
                            "token_signing_alg_values_expected": "RS256"
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
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /hello HTTP/1.1
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL3NhbXBsZXMuYXV0aDAuY29tLyIsInN1YiI6InRlc3Qtc3ViamVjdCIsImF1ZCI6ImtieXVG RGlkTExtMjgwTEl3VkZpYXpPcWpPM3R5OEtIIiwic2NvcGUiOiJhcGlzaXgiLCJpYXQiOjEwMDAwMDAwLCJleHAiOjI1MDAwMDAwMDB9.bfcZsd4ABgo0GoLT8EwfnKgf AWbnJZbZ3kOtqyeSkXYqGlSmgMNW3q5Kx1SGjMNhEKVG_KrFfsPrQmcTljSPZA
--- response_body
success



=== TEST 5: configure route with bearer_only + public_key + claim_schema that requires an absent field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                            "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                            "ssl_verify": false,
                            "bearer_only": true,
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAO6oZg+4sbTPa0oeKcfsJf2bx7N7JkGB\ngVqJeCkMHJ7lKLCTpg6P3UpTfNx5K+pKXsDucQbhjQqmjMwTBEe44EsCAwEAAQ==\n-----END PUBLIC KEY-----",
                            "token_signing_alg_values_expected": "RS256",
                            "claim_schema": {
                                "type": "object",
                                "required": ["email"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: bearer-path claim_schema rejection returns 401 with WWW-Authenticate header
--- request
GET /hello HTTP/1.1
--- more_headers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL3NhbXBsZXMuYXV0aDAuY29tLyIsInN1YiI6InRlc3Qtc3ViamVjdCIsImF1ZCI6ImtieXVGRGlkTExtMjgwTEl3VkZpYXpPcWpPM3R5OEtIIiwic2NvcGUiOiJhcGlzaXgiLCJpYXQiOjEwMDAwMDAwLCJleHAiOjI1MDAwMDAwMDB9.yWPMyXHuhiBP3q0xUkg3Iwu8dvXWlaVGBqPC8y8hC1MYoCcj687X85o9mvw1Mz_kGgKHNvDYrl5EQ3B3LAM4OA
--- error_code: 401
--- response_headers_like
WWW-Authenticate: Bearer realm="apisix", error="invalid_token".*
--- no_error_log
[crit]
[alert]
[emerg]
--- grep_error_log eval
qr/OIDC claim validation failed/
--- grep_error_log_out
OIDC claim validation failed
