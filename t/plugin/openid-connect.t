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
run_tests();

__DATA__

=== TEST 1: Sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"}
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: Missing `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_secret = "b",
                discovery = "c",
                session = {secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"}
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "client_id" is required
done



=== TEST 3: Wrong type for `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = 123,
                client_secret = "b",
                discovery = "c",
                session = {secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"}
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "client_id" validation failed: wrong type: expected string, got number
done



=== TEST 4: Set up new route with plugin matching URI `/hello`.
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
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "client_rsa_private_key": "89ae4c8edadf1cd1c9f034335f136f87ad84b625c8f1",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix",
                                "use_pkce": false,
                                "dpop": {
                                    "private_key": "dpop-private-key"
                                },
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 5: verify encrypted fields
--- config
    location /t {
        content_by_lua_block {
            -- get plugin conf from etcd, private key fields are encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            local conf = res.body.node.value.plugins["openid-connect"]
            ngx.say(type(conf.client_rsa_private_key) == "string"
                    and conf.client_rsa_private_key ~= "89ae4c8edadf1cd1c9f034335f136f87ad84b625c8f1")
            ngx.say(type(conf.dpop.private_key) == "string"
                    and conf.dpop.private_key ~= "dpop-private-key")

        }
    }
--- response_body
true
true



=== TEST 6: Access route w/o bearer token. Should redirect to authentication endpoint of ID provider.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=https://iresty.com') ~= -1 then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302



=== TEST 7: Modify route to match catch-all URI `/*` and point plugin to local Keycloak instance.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_header": true,
                                "set_refresh_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 8: Access route w/o bearer token and go through the full OIDC Relying Party authentication process.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            -- Make the final call back to the original URI.
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                -- No response, must be an error.
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 200 then
                -- Not a valid response.
                -- Use 500 to indicate error.
                ngx.status = 500
                ngx.say("Invoking the original URI didn't return the expected result.")
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- response_body_like
uri: /uri
cookie: .*
host: 127.0.0.1:1984
user-agent: .*
x-access-token: ey.*
x-id-token: ey.*
x-real-ip: 127.0.0.1
x-refresh-token: ey.*
x-userinfo: ey.*



=== TEST 9: Re-configure plugin with respect to headers that get sent to upstream.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": true,
                                "set_id_token_header": false,
                                "set_userinfo_header": false,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 10: Access route w/o bearer token and go through the full OIDC Relying Party authentication process.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            -- Make the final call back to the original URI.
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                -- No response, must be an error.
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 200 then
                -- Not a valid response.
                -- Use 500 to indicate error.
                ngx.status = 500
                ngx.say("Invoking the original URI didn't return the expected result.")
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- response_body_like
uri: /uri
authorization: Bearer ey.*
cookie: .*
host: 127.0.0.1:1984
user-agent: .*
x-real-ip: 127.0.0.1



=== TEST 11: Update plugin with `bearer_only=true`.
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
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix"
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



=== TEST 12: Access route w/o bearer token. Should return 401 (Unauthorized).
--- timeout: 10s
--- request
GET /hello
--- error_code: 401
--- response_headers_like
WWW-Authenticate: Bearer realm="apisix"
--- error_log
OIDC introspection failed: No bearer token found in request.



=== TEST 13: Access route with invalid Authorization header value. Should return 400 (Bad Request).
--- timeout: 10s
--- request
GET /hello
--- more_headers
Authorization: foo
--- error_code: 400
--- error_log
OIDC introspection failed: Invalid Authorization header format.



=== TEST 14: Update plugin with ID provider public key, so tokens can be validated locally.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256",
                                "claim_validator": {
                                    "issuer": {
                                        "valid_issuers": ["Mysoft corp"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: Access route with valid token.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = [[Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A]]
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- response_body
true



=== TEST 16: Update route URI to '/uri' where upstream endpoint returns request headers in response body.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256",
                                "claim_validator": {
                                    "issuer": {
                                        "valid_issuers": ["Mysoft corp"]
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
                        "uri": "/uri"
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



=== TEST 17: Access route with valid token in `Authorization` header. Upstream should additionally get the token in the `X-Access-Token` header.
--- request
GET /uri HTTP/1.1
--- more_headers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A
--- response_body_like
uri: /uri
authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A
host: localhost
x-access-token: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A
x-real-ip: 127.0.0.1
x-userinfo: ey.*
--- error_code: 200



=== TEST 18: Update plugin to only use `Authorization` header.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": true,
                                "set_id_token_header": false,
                                "set_userinfo_header": false,
                                "claim_validator": {
                                    "issuer": {
                                        "valid_issuers": ["Mysoft corp"]
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
                        "uri": "/uri"
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



=== TEST 19: Access route with valid token in `Authorization` header. Upstream should not get the additional `X-Access-Token` header.
--- request
GET /uri HTTP/1.1
--- more_headers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A
--- response_body
uri: /uri
authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.Vq_sBN7nH67vMDbiJE01EP4hvJYE_5ju6izjkOX8pF5OS4g2RWKWpL6h6-b0tTkCzG4JD5BEl13LWW-Gxxw0i9vEK0FLg_kC_kZLYB8WuQ6B9B9YwzmZ3OLbgnYzt_VD7D-7psEbwapJl5hbFsIjDgOAEx-UCmjUcl2frZxZavG2LUiEGs9Ri7KqOZmTLgNDMWfeWh1t1LyD0_b-eTInbasVtKQxMlb5kR0Ln_Qg5092L-irJ7dqaZma7HItCnzXJROdqJEsMIBAYRwDGa_w5kIACeMOdU85QKtMHzOenYFkm6zh_s59ndziTctKMz196Y8AL08xuTi6d1gEWpM92A
host: localhost
x-real-ip: 127.0.0.1
--- error_code: 200



=== TEST 20: Switch route URI back to `/hello`.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw\n]] ..
                                    [[94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD\n]] ..
                                    [[z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5\n]] ..
                                    [[sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO\n]] ..
                                    [[oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh\n]] ..
                                    [[G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD\n]] ..
                                    [[zQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256",
                                "claim_validator": {
                                    "issuer": {
                                        "valid_issuers": ["Mysoft corp"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: Access route with invalid token. Should return 401.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9" ..
                        ".eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk" ..
                        "4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCB" ..
                        "jb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqX" ..
                        "RyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- error_code: 401
--- error_log
jwt signature verification failed



=== TEST 22: Update route with Keycloak introspection endpoint and public key removed. Should now invoke introspection endpoint to validate tokens.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "realm": "University",
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
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



=== TEST 23: Obtain valid token and access route with it.
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })

                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- response_body
true
--- grep_error_log eval
qr/token validate successfully by \w+/
--- grep_error_log_out
token validate successfully by introspection



=== TEST 24: Access route with an invalid token.
--- config
    location /t {
        content_by_lua_block {
            -- Access route using a fake access token.
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- response_body
false
--- error_log
OIDC introspection failed: invalid token



=== TEST 25: Check defaults.
--- config
    location /t {
        content_by_lua_block {
            local json = require("t.toolkit.json")
            local plugin = require("apisix.plugins.openid-connect")
            local s = {
                client_id = "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                client_secret = "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                discovery = "http://127.0.0.1:1980/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
            }
            local ok, err = plugin.check_schema(s)
            if not ok then
                ngx.say(err)
            end

            ngx.say(json.encode(s))
        }
    }
--- response_body
{"accept_none_alg":false,"accept_unsupported_alg":true,"access_token_expires_leeway":0,"access_token_in_authorization_header":false,"bearer_only":false,"client_id":"kbyuFDidLLm280LIwVFiazOqjO3ty8KH","client_jwt_assertion_expires_in":60,"client_secret":"60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa","discovery":"http://127.0.0.1:1980/.well-known/openid-configuration","force_reauthorize":false,"iat_slack":120,"introspection_endpoint_auth_method":"client_secret_basic","introspection_interval":0,"jwk_expires_in":86400,"jwt_verification_cache_ignore":false,"logout_path":"/logout","realm":"apisix","renew_access_token_on_expiry":true,"revoke_tokens_on_logout":false,"scope":"openid","session":{"secret":"jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK","storage":"cookie"},"set_access_token_header":true,"set_id_token_header":true,"set_raw_id_token_header":false,"set_refresh_token_header":false,"set_userinfo_header":true,"ssl_verify":true,"timeout":3,"token_endpoint_auth_method":"client_secret_basic","unauth_action":"auth","use_jwks":false,"use_nonce":false,"use_pkce":false}



=== TEST 26: Update plugin with ID provider jwks endpoint for token verification.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "use_jwks": true,
                                "realm": "University",
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
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



=== TEST 27: Obtain valid token and access route with it.
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })

                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- response_body
true
--- grep_error_log eval
qr/token validate successfully by \w+/
--- grep_error_log_out
token validate successfully by jwks



=== TEST 28: Access route with an invalid token.
--- config
    location /t {
        content_by_lua_block {
            -- Access route using a fake access token.
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- response_body
false
--- error_log
OIDC introspection failed: invalid jwt: invalid jwt string



=== TEST 29: Modify route to match catch-all URI `/*` and add post_logout_redirect_uri option.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_header": true,
                                "post_logout_redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/hello",
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 30: Access route w/o bearer token and request logout to redirect to post_logout_redirect_uri.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])

            -- Request the logout uri with the log-in cookie
            local logout_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            res, err = httpc:request_uri(logout_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
            })
            if not res then
                -- No response, must be an error
                -- Use 500 to indicate error
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 302 then
                ngx.status = 500
                ngx.say("Request the logout URI didn't return the expected status.")
                return
            end

            -- Request the location, it's a URL of keycloak and contains the post_logout_redirect_uri
            -- Like:
            -- http://127.0.0.1:8080/realms/University/protocol/openid-connect/logout?post_logout_redirect=http://127.0.0.1:1984/hello
            local location = res.headers["Location"]
            res, err = httpc:request_uri(location, {
               method = "GET"
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 302 then
                ngx.status = 500
                ngx.say("Request the keycloak didn't return the expected status.")
                return
            end

            ngx.status = 200
            ngx.say(res.headers["Location"])
        }
    }
--- response_body_like
http://127.0.0.1:.*/hello



=== TEST 31: Switch route URI back to `/hello` and enable pkce.
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
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix",
                                "use_pkce": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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



=== TEST 32: Access route w/o bearer token. Should redirect to authentication endpoint of ID provider with code_challenge parameters.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=https://iresty.com') ~= -1 and
                string.match(location, '.*code_challenge=.*') and
                string.match(location, '.*code_challenge_method=S256.*') then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302



=== TEST 33: set use_jwks and set_userinfo_header to validate "x-userinfo" in request header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "bearer_only": true,
                                "access_token_in_authorization_header": true,
                                "set_userinfo_header": true,
                                "use_jwks": true,
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 34: Access route to validate "x-userinfo" in request header
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })

                if not res then
                    -- No response, must be an error.
                    ngx.status = 500
                    ngx.say(err)
                    return
                elseif res.status ~= 200 then
                    -- Not a valid response.
                    -- Use 500 to indicate error.
                    ngx.status = 500
                    ngx.say("Invoking the original URI didn't return the expected result.")
                    return
                end

                ngx.status = res.status
                ngx.say(res.body)

            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- response_body_like
x-userinfo: ey.*



=== TEST 35: Set up new route with plugin matching URI `/*`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "post_logout_redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "scope": "openid profile",
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 36: Redirect to post_logout_redirect_uri when provider has no end_session_endpoint
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = ngx.unescape_uri(res.headers['Location'] or "")
            if location:find('https://iresty.com', 1, true) and
                location:find('post_logout_redirect_uri=https://iresty.com', 1, true) then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302



=== TEST 37: Set up new route with plugin matching URI `/*`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration-with-end-session",
                                "redirect_uri": "https://iresty.com",
                                "post_logout_redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "scope": "openid profile",
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 38: Redirect to end_session_endpoint with post_logout_redirect_uri when provider exposes it
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = ngx.unescape_uri(res.headers['Location'] or "")
            if location:find('https://samples.auth0.com/v2/logout', 1, true) and
                location:find('post_logout_redirect_uri=https://iresty.com', 1, true) then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302



=== TEST 39: Update plugin config to use_jwk and bear_only false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": false,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                },
                                "use_jwks": true,
                                "realm": "University",
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token/introspect"
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



=== TEST 40: Test that jwt with bearer_only false still allows a valid Authorization header
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8080/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })

                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- response_body
true
--- grep_error_log eval
qr/token validate successfully by \w+/
--- grep_error_log_out
token validate successfully by jwks



=== TEST 41: Missing `session.secret`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "session.secret" is required when "bearer_only" is false
done



=== TEST 42: client_secret is optional when bearer_only=true and public_key is set.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = true,
                public_key = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2a2rwplBQLzHPZe5TNJF\n-----END PUBLIC KEY-----",
                token_signing_alg_values_expected = "RS256",
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 43: client_secret is optional when bearer_only=true and use_jwks=true.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = true,
                use_jwks = true,
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 44: client_secret is required when bearer_only=true but neither public_key nor use_jwks is set (introspection mode).
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = true,
                introspection_endpoint = "https://example.com/introspect",
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "client_secret" is required
done



=== TEST 45: client_secret is optional when token_endpoint_auth_method=private_key_jwt.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = false,
                token_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 46: client_secret is optional when use_pkce=true (non-bearer PKCE flow).
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = false,
                use_pkce = true,
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 47: client_secret is still required for non-bearer session flow without special auth method.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = false,
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "client_secret" is required
done



=== TEST 48: client_secret is optional when bearer_only=true and introspection_endpoint_auth_method=private_key_jwt.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = true,
                introspection_endpoint = "https://example.com/introspect",
                introspection_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 49: client_secret stays required for bearer introspection even with token_endpoint_auth_method=private_key_jwt (cross-flow: that method does not apply to introspection).
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = true,
                introspection_endpoint = "https://example.com/introspect",
                token_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "client_secret" is required
done



=== TEST 50: client_secret stays required for non-bearer session flow with a bearer-only alternative (introspection private_key_jwt does not apply here).
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = false,
                introspection_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "client_secret" is required
done



=== TEST 51a: Accept PAR, DPoP, and client assertion algorithm options.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                bearer_only = false,
                use_pkce = true,
                par = {
                    enabled = true,
                    endpoint = "https://example.com/par",
                    endpoint_auth_method = "private_key_jwt",
                },
                dpop = {
                    enabled = true,
                    signing_alg = "ES256",
                    -- a real key pair: the private key has to load and match
                    -- the algorithm, and the JWK is derived from it
                    private_key = "-----BEGIN PRIVATE KEY-----\n"
                        .. "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgzVW+Se78iBpOnKwj\n"
                        .. "D0Gqp/ZpmFSVJPRSTI7ZU50g3s2hRANCAARJ6hd/fMq/ZLvdEu1ZKHWFmiTjL1LD\n"
                        .. "U4q5hU/UxozQRW7+Gr5bcSvgHJWK/PlNCN/NGISpRs3K3l3K0BUr7plo\n"
                        .. "-----END PRIVATE KEY-----",
                    public_jwk = {
                        kty = "EC",
                        crv = "P-256",
                        x = "SeoXf3zKv2S73RLtWSh1hZok4y9Sw1OKuYVP1MaM0EU",
                        y = "bv4avltxK-AclYr8-U0I380YhKlGzcreXcrQFSvumWg",
                    },
                },
                token_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
                client_jwt_assertion_alg = "RS512",
                client_jwt_assertion_audience = "https://issuer.example.com/token",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 52b: Reject unsupported DPoP signing algorithm in schema.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://example.com/.well-known/openid-configuration",
                dpop = {
                    signing_alg = "HS256",
                },
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "dpop" validation failed: property "signing_alg" validation failed: matches none of the enum values
done



=== TEST 53c: Accept PAR enabled without endpoint in schema.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://example.com/.well-known/openid-configuration",
                par = {
                    enabled = true,
                },
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 54d: Reject DPoP enabled without key material in schema.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://example.com/.well-known/openid-configuration",
                dpop = {
                    enabled = true,
                },
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "dpop" validation failed: then clause did not match
done



=== TEST 55e: Reject private key material in DPoP public JWK.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://example.com/.well-known/openid-configuration",
                dpop = {
                    enabled = true,
                    private_key = "-----BEGIN PRIVATE KEY-----\nMIIEowIBAAK\n-----END PRIVATE KEY-----",
                    public_jwk = {
                        kty = "RSA",
                        e = "AQAB",
                        n = "abc",
                        d = "private-exponent",
                    },
                },
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body_like
property "dpop" validation failed: property "public_jwk" validation failed:.*
done



=== TEST 56: PAR runtime mapping sends authorization parameters through PAR.
--- http_config
    server {
        listen 16969;
        server_name localhost;

        location /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{
                    "issuer": "http://127.0.0.1:16969",
                    "authorization_endpoint": "http://127.0.0.1:16969/authorize",
                    "token_endpoint": "http://127.0.0.1:16969/token",
                    "userinfo_endpoint": "http://127.0.0.1:16969/userinfo",
                    "jwks_uri": "http://127.0.0.1:16969/jwks"
                }]])
            }
        }

        location /par {
            content_by_lua_block {
                ngx.req.read_body()
                local args = ngx.req.get_post_args()
                if args.scope ~= "openid email" or not args.state then
                    ngx.status = 400
                    ngx.say([[{"error":"invalid_request"}]])
                    return
                end

                -- only client_secret_post sends the credentials in the body;
                -- without this the par.endpoint_auth_method mapping is not
                -- really tested, because dropping it falls back to
                -- token_endpoint_auth_method, which defaults to
                -- client_secret_basic and would be accepted here too
                if args.client_id ~= "test_client"
                   or args.client_secret ~= "test_secret" then
                    ngx.status = 400
                    ngx.say([[{"error":"invalid_client"}]])
                    return
                end

                ngx.header.content_type = "application/json"
                ngx.say([[{
                    "request_uri": "urn:ietf:params:oauth:request_uri:par-runtime",
                    "expires_in": 60
                }]])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "test_client",
                            "client_secret": "test_secret",
                            "discovery": "http://127.0.0.1:16969/.well-known/openid-configuration",
                            "redirect_uri": "http://127.0.0.1:]=] .. ngx.var.server_port .. [=[/callback",
                            "ssl_verify": false,
                            "timeout": 10,
                            "scope": "openid email",
                            "par": {
                                "enabled": true,
                                "endpoint": "http://127.0.0.1:16969/par",
                                "endpoint_auth_method": "client_secret_post"
                            },
                            "session": {
                                "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/par-runtime"
                }]=])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/par-runtime"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = res.status
            local location = res.headers["Location"] or ""
            local query = string.match(location, "^http://127%.0%.0%.1:16969/authorize%?(.*)$")
            local args = query and ngx.decode_args(query) or {}
            local core = require("apisix.core")

            ngx.say(query ~= nil)
            ngx.say(core.table.nkeys(args) == 2)
            ngx.say(args.client_id == "test_client")
            ngx.say(args.request_uri == "urn:ietf:params:oauth:request_uri:par-runtime")
            ngx.say(args.scope == nil)
            ngx.say(args.state == nil)
            ngx.say(args.response_type == nil)
            ngx.say(args.redirect_uri == nil)
        }
    }
--- timeout: 10s
--- response_body
true
true
true
true
true
true
true
true
--- error_code: 302



=== TEST 57: Configure plugin with a custom session.cookie_name.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    "cookie_name": "custom_session"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 58: Full OIDC login issues the session cookie under the configured cookie_name.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            -- The session cookie must use the configured name, not the default "session".
            if not cookie_str:find("custom_session=", 1, true) then
                ngx.status = 500
                ngx.say("expected custom_session cookie, got: " .. cookie_str)
                return
            end

            -- The renamed cookie must be a working session: the protected URI returns 200.
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request with renamed cookie failed: " .. res.status)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 59: Configure plugin with a short session.absolute_timeout.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    "absolute_timeout": 5
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 60: Session is rejected once absolute_timeout elapses, re-initiating authentication.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])

            -- Right after login the session is valid.
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']
            local res1 = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = { ["Cookie"] = cookie_str }
                })
            if not res1 or res1.status ~= 200 then
                ngx.status = 500
                ngx.say("session should be valid right after login, got: "
                        .. (res1 and res1.status or "nil"))
                return
            end

            -- Once absolute_timeout (5s) passes, the session is no longer accepted
            -- and the request is redirected back to the ID provider for re-authentication.
            ngx.sleep(6)
            local res2 = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["Cookie"] = cookie_str }
                })
            if not res2 then
                ngx.status = 500
                ngx.say("no response after timeout")
                return
            elseif res2.status ~= 302 then
                ngx.status = 500
                ngx.say("expired session should trigger re-auth (302), got: " .. res2.status)
                return
            end

            -- The redirect must go back to the IdP authorization endpoint, i.e. a
            -- fresh OIDC flow, not some other redirect.
            local location = res2.headers['Location'] or ""
            if not location:find("/protocol/openid-connect/auth", 1, true) then
                ngx.status = 500
                ngx.say("expected redirect to IdP authorization endpoint, got: " .. location)
                return
            end

            ngx.say("passed")
        }
    }
--- timeout: 20
--- response_body
passed



=== TEST 61: Configure plugin with set_raw_id_token_header enabled.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "set_access_token_header": false,
                                "set_id_token_header": false,
                                "set_userinfo_header": false,
                                "set_raw_id_token_header": true,
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 62: Full OIDC login sets X-Raw-ID-Token with the raw signed JWT; other auth headers are absent.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie_str = concatenate_cookies(res.headers['Set-Cookie'])
            local redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']
            res, err = httpc:request_uri(redirect_uri, {
                    method = "GET",
                    headers = {
                        ["Cookie"] = cookie_str
                    }
                })

            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 200 then
                ngx.status = 500
                ngx.say("Invoking the original URI didn't return the expected result.")
                return
            end

            -- X-Raw-ID-Token must be present and contain a JWT (starts with "ey").
            if not res.body:find("x-raw-id-token: ey", 1, true) then
                ngx.status = 500
                ngx.say("expected x-raw-id-token header with a JWT value, body: " .. res.body)
                return
            end

            -- The other auth headers must be absent (set_*_header = false).
            for _, unwanted in ipairs({"x-access-token:", "x-id-token:", "x-userinfo:"}) do
                if res.body:find(unwanted, 1, true) then
                    ngx.status = 500
                    ngx.say("unexpected header found: " .. unwanted)
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 63: Reject a client assertion algorithm resty.jwt cannot sign.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                token_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAK\n-----END RSA PRIVATE KEY-----",
                client_jwt_assertion_alg = "PS256",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "client_jwt_assertion_alg" validation failed: matches none of the enum values
done



=== TEST 64: Every nested option is flattened to the name lua-resty-openidc reads.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local jwk = {kty = "RSA", e = "AQAB", n = "abc"}
            local conf = {
                par = {
                    enabled = true,
                    endpoint = "https://example.com/par",
                    endpoint_auth_method = "private_key_jwt",
                },
                dpop = {
                    enabled = true,
                    signing_alg = "PS256",
                    private_key = "dpop-private-key",
                    public_jwk = jwk,
                },
            }
            plugin._flatten_openidc_options(conf)

            ngx.say(conf.use_par == true)
            ngx.say(conf.pushed_authorization_request_endpoint
                    == "https://example.com/par")
            ngx.say(conf.pushed_authorization_request_endpoint_auth_method
                    == "private_key_jwt")
            ngx.say(conf.use_dpop == true)
            ngx.say(conf.dpop_signing_alg == "PS256")
            ngx.say(conf.dpop_private_key == "dpop-private-key")
            ngx.say(conf.dpop_public_jwk == jwk)
            -- the nested tables must not survive into the opts handed to
            -- lua-resty-openidc
            ngx.say(conf.par == nil)
            ngx.say(conf.dpop == nil)
        }
    }
--- response_body
true
true
true
true
true
true
true
true
true



=== TEST 65: A conf without par or dpop is left alone by the flattening.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local conf = {client_id = "a"}
            plugin._flatten_openidc_options(conf)

            ngx.say(conf.use_par == nil)
            ngx.say(conf.use_dpop == nil)
            ngx.say(conf.dpop_public_jwk == nil)
            ngx.say(conf.client_id == "a")
        }
    }
--- response_body
true
true
true
true



=== TEST 66: Introspection sends the client credentials per introspection_endpoint_auth_method.
--- http_config
    server {
        listen 16969;
        server_name localhost;

        location /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{
                    "issuer": "http://127.0.0.1:16969",
                    "authorization_endpoint": "http://127.0.0.1:16969/authorize",
                    "token_endpoint": "http://127.0.0.1:16969/token",
                    "userinfo_endpoint": "http://127.0.0.1:16969/userinfo",
                    "jwks_uri": "http://127.0.0.1:16969/jwks"
                }]])
            }
        }

        # lua-resty-openidc 1.9.0 only puts the credentials in the POST body
        # when introspection_endpoint_auth_method is nil, and this Plugin
        # defaults it to client_secret_basic. Report where they actually
        # arrived so both halves of that behavior are pinned.
        location /introspect {
            content_by_lua_block {
                ngx.req.read_body()
                local args = ngx.req.get_post_args()
                local in_body = args.client_id == "test_client"
                                and args.client_secret == "test_secret"
                local expected = "Basic " .. ngx.encode_base64(
                    ngx.escape_uri("test_client") .. ":"
                    .. ngx.escape_uri("test_secret"))
                local in_header = ngx.var.http_authorization == expected

                ngx.header.content_type = "application/json"
                ngx.say([[{"active":true,"body":]] .. tostring(in_body)
                        .. [[,"header":]] .. tostring(in_header) .. [[}]])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local function probe(auth_method, token)
                local conf = [=[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "test_client",
                            "client_secret": "test_secret",
                            "discovery": "http://127.0.0.1:16969/.well-known/openid-configuration",
                            "introspection_endpoint": "http://127.0.0.1:16969/introspect",
                            "bearer_only": true,
                            "ssl_verify": false,
                            "timeout": 10,
                            "set_userinfo_header": true]=]
                if auth_method then
                    conf = conf .. [=[,
                            "introspection_endpoint_auth_method": "]=]
                           .. auth_method .. [=["]=]
                end
                conf = conf .. [=[
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/uri"
                }]=]

                local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, conf)
                if code >= 300 then
                    return "route failed: " .. code
                end

                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
                local res, err = http.new():request_uri(uri, {
                    method = "GET",
                    headers = {["Authorization"] = "Bearer " .. token},
                })
                if not res then
                    return "request failed: " .. err
                end
                -- the introspection result reaches the upstream base64-encoded
                -- in X-Userinfo; /uri echoes the request headers back
                local encoded = res.body:match("x%-userinfo: ([%w+/=]+)")
                if not encoded then
                    return "no x-userinfo, status " .. res.status
                end
                local core = require("apisix.core")
                local seen = core.json.decode(ngx.decode_base64(encoded))
                -- assert on the decoded fields, not on the key order the
                -- library happens to re-encode them in
                return "body=" .. tostring(seen.body)
                       .. " header=" .. tostring(seen.header)
            end

            -- the default is client_secret_basic, so the body carries nothing
            ngx.say(probe(nil, "tok-default"))
            ngx.say(probe("client_secret_basic", "tok-basic"))
            ngx.say(probe("client_secret_post", "tok-post"))
        }
    }
--- timeout: 10s
--- response_body
body=false header=true
body=false header=true
body=true header=false



=== TEST 67: Reject the flat lua-resty-openidc option names the par and dpop objects own.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local flat = {
                {use_par = true},
                {pushed_authorization_request_endpoint = "https://example.com/par"},
                {pushed_authorization_request_endpoint_auth_method = "private_key_jwt"},
                {use_dpop = true},
                {dpop_signing_alg = "RS256"},
                {dpop_private_key = "plaintext-key"},
                {dpop_public_jwk = {kty = "RSA", e = "AQAB", n = "abc"}},
            }
            for _, extra in ipairs(flat) do
                local conf = {
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                }
                for k, v in pairs(extra) do conf[k] = v end
                local ok, err = plugin.check_schema(conf)
                ngx.say(ok and "ACCEPTED" or err)
            end
        }
    }
--- response_body
property "use_par" is not allowed, use "par.enabled" instead
property "pushed_authorization_request_endpoint" is not allowed, use "par.endpoint" instead
property "pushed_authorization_request_endpoint_auth_method" is not allowed, use "par.endpoint_auth_method" instead
property "use_dpop" is not allowed, use "dpop.enabled" instead
property "dpop_signing_alg" is not allowed, use "dpop.signing_alg" instead
property "dpop_private_key" is not allowed, use "dpop.private_key" instead
property "dpop_public_jwk" is not allowed, use "dpop.public_jwk" instead



=== TEST 68: The Admin API rejects a flat DPoP private key instead of storing it in plaintext.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "a",
                            "client_secret": "b",
                            "discovery": "https://example.com/.well-known/openid-configuration",
                            "use_dpop": true,
                            "dpop_private_key": "plaintext-key",
                            "dpop_public_jwk": {"kty": "RSA", "e": "AQAB", "n": "abc"},
                            "session": {"secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"}
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]])

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/property \\"use_dpop\\" is not allowed, use \\"dpop.enabled\\" instead/



=== TEST 69: Reject a DPoP public JWK that lua-resty-openidc cannot build a thumbprint from.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local jwks = {
                {kty = "RSA"},
                {kty = "EC", crv = "P-256"},
                {kty = "OKP", x = "abc"},
            }
            for _, jwk in ipairs(jwks) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    dpop = {
                        enabled = true,
                        signing_alg = jwk.kty == "RSA" and "RS256" or "ES256",
                        private_key = "-----BEGIN PRIVATE KEY-----\nMIIEowIBAAK\n-----END PRIVATE KEY-----",
                        public_jwk = jwk,
                    },
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                })
                ngx.say(ok and "ACCEPTED" or err)
            end
        }
    }
--- response_body
property "dpop.public_jwk" validation failed: kty "RSA" requires e, n
property "dpop.public_jwk" validation failed: kty "EC" requires crv, x, y
property "dpop.public_jwk" validation failed: kty "OKP" is not supported



=== TEST 70: Reject a DPoP signing algorithm that does not match the public JWK key type.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local cases = {
                {alg = "ES256", jwk = {kty = "RSA", e = "AQAB", n = "abc"}},
                {alg = "RS256", jwk = {kty = "EC", crv = "P-256", x = "a", y = "b"}},
                {alg = "PS256", jwk = {kty = "EC", crv = "P-256", x = "a", y = "b"}},
            }
            for _, case in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    dpop = {
                        enabled = true,
                        signing_alg = case.alg,
                        private_key = "-----BEGIN PRIVATE KEY-----\nMIIEowIBAAK\n-----END PRIVATE KEY-----",
                        public_jwk = case.jwk,
                    },
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                })
                ngx.say(ok and "ACCEPTED" or err)
            end
        }
    }
--- response_body
property "dpop.signing_alg" "ES256" requires an EC "dpop.public_jwk"
property "dpop.signing_alg" "RS256" requires an RSA "dpop.public_jwk"
property "dpop.signing_alg" "PS256" requires an RSA "dpop.public_jwk"



=== TEST 71: Reject a client assertion algorithm whose family the endpoint auth method rejects.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local cases = {
                {token_endpoint_auth_method = "private_key_jwt",
                 client_rsa_private_key = "k", client_jwt_assertion_alg = "HS256"},
                {introspection_endpoint_auth_method = "private_key_jwt",
                 bearer_only = true, public_key = "k", client_jwt_assertion_alg = "HS512"},
                {token_endpoint_auth_method = "client_secret_jwt",
                 client_jwt_assertion_alg = "RS256"},
                {par = {enabled = true, endpoint_auth_method = "client_secret_jwt"},
                 client_jwt_assertion_alg = "ES256"},
                {token_endpoint_auth_method = "private_key_jwt",
                 client_rsa_private_key = "k",
                 introspection_endpoint_auth_method = "client_secret_jwt",
                 client_jwt_assertion_alg = "RS256"},
            }
            for _, extra in ipairs(cases) do
                local conf = {
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                }
                for k, v in pairs(extra) do conf[k] = v end
                local ok, err = plugin.check_schema(conf)
                ngx.say(ok and "ACCEPTED" or err)
            end
        }
    }
--- response_body
property "client_jwt_assertion_alg" "HS256" is symmetric and cannot be used with the private_key_jwt selected by "token_endpoint_auth_method"
property "client_jwt_assertion_alg" "HS512" is symmetric and cannot be used with the private_key_jwt selected by "introspection_endpoint_auth_method"
property "client_jwt_assertion_alg" "RS256" is asymmetric and cannot be used with the client_secret_jwt selected by "token_endpoint_auth_method"
property "client_jwt_assertion_alg" "ES256" is asymmetric and cannot be used with the client_secret_jwt selected by "par.endpoint_auth_method"
property "client_jwt_assertion_alg" is a single algorithm, but "token_endpoint_auth_method" selects private_key_jwt and "introspection_endpoint_auth_method" selects client_secret_jwt



=== TEST 72: Accept both JWT auth families when no client assertion algorithm is configured.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            -- lua-resty-openidc then picks RS256 or HS256 per auth method,
            -- so the families cannot conflict
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://example.com/.well-known/openid-configuration",
                token_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "k",
                introspection_endpoint_auth_method = "client_secret_jwt",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 73: Reject a DPoP public JWK whose members are not usable in a thumbprint.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local cases = {
                -- ES256 is P-256 only per RFC 7518; another curve produces a
                -- proof the OP cannot verify
                {alg = "ES256", jwk = {kty = "EC", crv = "P-384", x = "x", y = "y"}},
                {alg = "ES256", jwk = {kty = "EC", crv = "P-256", x = 1, y = "y"}},
                {alg = "ES256", jwk = {kty = "EC", crv = "P-256", x = "x", y = ""}},
                {alg = "RS256", jwk = {kty = "RSA", e = "AQAB", n = ""}},
                {alg = "RS256", jwk = {kty = "RSA", e = true, n = "abc"}},
            }
            for _, case in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    dpop = {
                        enabled = true,
                        signing_alg = case.alg,
                        private_key = "-----BEGIN PRIVATE KEY-----\nMIIEowIBAAK\n-----END PRIVATE KEY-----",
                        public_jwk = case.jwk,
                    },
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                })
                ngx.say(ok and "ACCEPTED" or err)
            end
        }
    }
--- response_body
property "dpop.signing_alg" "ES256" requires "dpop.public_jwk" crv "P-256", got "P-384"
property "dpop.public_jwk" validation failed: "x" must be a non-empty string
property "dpop.public_jwk" validation failed: "y" must be a non-empty string
property "dpop.public_jwk" validation failed: "n" must be a non-empty string
property "dpop.public_jwk" validation failed: "e" must be a non-empty string



=== TEST 74: Reject a PAR authentication method lua-resty-openidc cannot use.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local base = {
                client_id = "a",
                discovery = "https://example.com/.well-known/openid-configuration",
                use_pkce = true,
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            }
            local function check(extra)
                local conf = {}
                for k, v in pairs(base) do conf[k] = v end
                for k, v in pairs(extra) do conf[k] = v end
                local ok, err = plugin.check_schema(conf)
                ngx.say(ok and "ACCEPTED" or err)
            end

            -- unknown method
            check({par = {enabled = true, endpoint_auth_method = "bogus"}})
            -- supported methods missing the credential they need
            check({par = {enabled = true, endpoint_auth_method = "private_key_jwt"}})
            check({par = {enabled = true, endpoint_auth_method = "client_secret_jwt"}})
            -- PAR falls back to token_endpoint_auth_method when it has none
            check({token_endpoint_auth_method = "private_key_jwt",
                   par = {enabled = true}})
        }
    }
--- response_body
property "par" validation failed: property "endpoint_auth_method" validation failed: matches none of the enum values
property "par.endpoint_auth_method" "private_key_jwt" requires "client_rsa_private_key" when "par.enabled" is true
property "par.endpoint_auth_method" "client_secret_jwt" requires "client_secret" when "par.enabled" is true
property "token_endpoint_auth_method" "private_key_jwt" requires "client_rsa_private_key" when "par.enabled" is true



=== TEST 75: Accept PAR authentication methods that have their credential.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local cases = {
                -- the schema default for token_endpoint_auth_method is
                -- client_secret_basic, which needs no extra credential
                {client_secret = "s", par = {enabled = true}},
                {client_secret = "s",
                 par = {enabled = true, endpoint_auth_method = "client_secret_post"}},
                {client_secret = "s",
                 par = {enabled = true, endpoint_auth_method = "client_secret_jwt"}},
                {client_secret = "s", client_rsa_private_key = "k",
                 par = {enabled = true, endpoint_auth_method = "private_key_jwt"}},
                -- an unusable method only breaks PAR, so it stays valid while
                -- PAR is off: the token endpoint falls back on its own
                {client_secret = "s", token_endpoint_auth_method = "private_key_jwt",
                 par = {enabled = false}},
            }
            for _, extra in ipairs(cases) do
                local conf = {
                    client_id = "a",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    use_pkce = true,
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                }
                for k, v in pairs(extra) do conf[k] = v end
                local ok, err = plugin.check_schema(conf)
                ngx.say(ok and "accepted" or err)
            end
        }
    }
--- response_body
accepted
accepted
accepted
accepted
accepted



=== TEST 76: Reject a DPoP private key that cannot be loaded or does not match the algorithm.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ec_key = "-----BEGIN PRIVATE KEY-----\n"
                .. "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgzVW+Se78iBpOnKwj\n"
                .. "D0Gqp/ZpmFSVJPRSTI7ZU50g3s2hRANCAARJ6hd/fMq/ZLvdEu1ZKHWFmiTjL1LD\n"
                .. "U4q5hU/UxozQRW7+Gr5bcSvgHJWK/PlNCN/NGISpRs3K3l3K0BUr7plo\n"
                .. "-----END PRIVATE KEY-----"
            local ec_jwk = {kty = "EC", crv = "P-256",
                            x = "SeoXf3zKv2S73RLtWSh1hZok4y9Sw1OKuYVP1MaM0EU",
                            y = "bv4avltxK-AclYr8-U0I380YhKlGzcreXcrQFSvumWg"}
            local cases = {
                -- not a key at all
                {alg = "ES256", key = "-----BEGIN PRIVATE KEY-----\nnope\n-----END PRIVATE KEY-----",
                 jwk = ec_jwk},
                -- a real key, but RS256 signs with an RSA one
                {alg = "RS256", key = ec_key, jwk = {kty = "RSA", e = "AQAB", n = "abc"}},
            }
            for _, case in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    dpop = {enabled = true, signing_alg = case.alg,
                            private_key = case.key, public_jwk = case.jwk},
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                })
                if ok then
                    ngx.say("ACCEPTED")
                else
                    -- the openssl error text varies by version
                    ngx.say((err:gsub("key: .*", "key")))
                end
            end
        }
    }
--- response_body
property "dpop.private_key" is not a valid key
property "dpop.private_key" is not an RSA key, which "dpop.signing_alg" "RS256" requires



=== TEST 77: Key material staged before DPoP is enabled stays valid.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            -- lua-resty-openidc reads none of it while use_dpop is false, so
            -- none of the DPoP checks may fire yet
            local cases = {
                {public_jwk = {kty = "RSA", e = "AQAB", n = "abc"}},
                {enabled = false, signing_alg = "ES256",
                 public_jwk = {kty = "RSA", e = "AQAB", n = "abc"}},
                {enabled = false, private_key = "not-a-key",
                 public_jwk = {kty = "EC", crv = "P-384", x = "x", y = "y"}},
            }
            for _, dpop in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "https://example.com/.well-known/openid-configuration",
                    dpop = dpop,
                    session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                })
                ngx.say(ok and "accepted" or err)
            end
        }
    }
--- response_body
accepted
accepted
accepted



=== TEST 78: bearer_only only ever calls the introspection endpoint.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            -- the token and PAR endpoints belong to the authorization code
            -- flow, which bearer_only never runs, so their auth method cannot
            -- conflict with the introspection one
            local ok, err = plugin.check_schema({
                client_id = "a",
                bearer_only = true,
                public_key = "k",
                discovery = "https://example.com/.well-known/openid-configuration",
                introspection_endpoint_auth_method = "private_key_jwt",
                client_rsa_private_key = "k",
                token_endpoint_auth_method = "client_secret_jwt",
                client_jwt_assertion_alg = "RS256",
                session = { secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done
