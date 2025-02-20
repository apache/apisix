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
            local ok, err = plugin.check_schema({client_id = "a", client_secret = "b", discovery = "c"})
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
            local ok, err = plugin.check_schema({client_secret = "b", discovery = "c"})
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
            local ok, err = plugin.check_schema({client_id = 123, client_secret = "b", discovery = "c"})
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
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix",
                                "use_pkce": false
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



=== TEST 5: verify encrypted field
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test


            -- get plugin conf from etcd, client_rsa_private_key is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["openid-connect"].client_rsa_private_key)

        }
    }
--- response_body
qO8TJbXcxCUnkkaTs3PxWDk5a54lv7FmngKQaxuXV4cL+7Kp1R4D8NS4w88so4e+



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
            if location and string.find(location, 'http://127.0.0.1:8080/realms/basic/protocol/openid-connect/auth') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=apisix') ~= -1 and
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
                                "set_refresh_token_header": true
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
                                "set_userinfo_header": false
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
                                "token_signing_alg_values_expected": "RS256"
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
                                "set_userinfo_header": false
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
            }
            local ok, err = plugin.check_schema(s)
            if not ok then
                ngx.say(err)
            end

            -- ensure session secret generated when bearer_only = false
            -- then remove it from table, because it's a random value that I cannot verify it by response body
            assert(s.session and s.session.secret, "no session secret generated")
            s.session = nil

            ngx.say(json.encode(s))
        }
    }
--- response_body
{"accept_none_alg":false,"accept_unsupported_alg":true,"access_token_expires_leeway":0,"access_token_in_authorization_header":false,"bearer_only":false,"client_id":"kbyuFDidLLm280LIwVFiazOqjO3ty8KH","client_jwt_assertion_expires_in":60,"client_secret":"60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa","discovery":"http://127.0.0.1:1980/.well-known/openid-configuration","force_reauthorize":false,"iat_slack":120,"introspection_endpoint_auth_method":"client_secret_basic","introspection_interval":0,"jwk_expires_in":86400,"jwt_verification_cache_ignore":false,"logout_path":"/logout","realm":"apisix","renew_access_token_on_expiry":true,"revoke_tokens_on_logout":false,"scope":"openid","set_access_token_header":true,"set_id_token_header":true,"set_refresh_token_header":false,"set_userinfo_header":true,"ssl_verify":false,"timeout":3,"token_endpoint_auth_method":"client_secret_basic","unauth_action":"auth","use_nonce":false,"use_pkce":false}



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
                                "post_logout_redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/hello"
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
                                "use_pkce": true
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
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "post_logout_redirect_uri": "https://iresty.com",
                                "scope": "openid profile"
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



=== TEST 36: Check whether auth0 can redirect normally using post_logout_redirect_uri configuration
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://iresty.com') ~= -1 and
                string.find(location, 'post_logout_redirect_uri=https://iresty.com') ~= -1 then
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
                                "client_id": "942299072001-vhduu1uljmdhhbbp7g22m3qsmo246a75.apps.googleusercontent.com",
                                "client_secret": "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",
                                "discovery": "https://accounts.google.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "post_logout_redirect_uri": "https://iresty.com",
                                "scope": "openid profile"
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



=== TEST 38: Check whether google can redirect normally using post_logout_redirect_uri configuration
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://iresty.com') ~= -1 and
                string.find(location, 'post_logout_redirect_uri=https://iresty.com') ~= -1 then
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
