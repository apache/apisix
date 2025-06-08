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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {
                    name = "sanity (bearer_only = true)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = true},
                    cb = function(ok, err, case)
                        assert(ok and not case.session, "not expect session was generated")
                    end,
                },
                {
                    name = "sanity (bearer_only = false)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false},
                    cb = function(ok, err, case)
                        assert(ok and case.session and case.session.secret, "no session secret generated")
                    end,
                },
                {
                    name = "sanity (bearer_only = false, user-set secret, less than 16 characters)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false, session = {secret = "test"}},
                    cb = function(ok, err, case)
                        assert(not ok and err == "property \"session\" validation failed: property \"secret\" validation failed: string too short, expected at least 16, got 4", "too short key passes validation")
                    end,
                },
                {
                    name = "sanity (bearer_only = false, user-set secret, more than 16 characters)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false, session = {secret = "test_secret_more_than_16"}},
                    cb = function(ok, err, case)
                        assert(ok and case.session and case.session.secret and case.session.secret == "test_secret_more_than_16", "user-set secret is incorrect")
                    end,
                },
            }

            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case.data)
                case.cb(ok, err, case.data)
            end
        }
    }



=== TEST 2: data encryption for client_secret
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
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
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
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["openid-connect"].client_secret)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["openid-connect"].client_secret)
        }
    }
--- response_body
60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa
xMlerg8pE2lPSDlQdPi+MsAwBnzqpyLRar3lUhP2Tdc2oXnWmit92p8cannhDYkBPc6P/Hlx0wSA0T2wle9QyHaW2oqw3bXDQSWWk8Vqq0o=



=== TEST 3: Set up route with plugin matching URI `/hello` with unauth_action = "auth".
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
                                "unauth_action": "auth",
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



=== TEST 4: Access route w/o bearer token. Should redirect to authentication endpoint of ID provider.
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



=== TEST 5: Set up route with plugin matching URI `/hello` with unauth_action = "deny".
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
                                "unauth_action": "deny",
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



=== TEST 6: Access route w/o bearer token. Should return unauthorized.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            ngx.say(true)
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 401



=== TEST 7: Set up route with plugin matching URI `/hello` with unauth_action = "pass".
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
                                "unauth_action": "pass",
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



=== TEST 8: Access route w/o bearer token. Should return ok.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true



=== TEST 9: Set up route with plugin matching URI `/hello` with redirect_uri use default value.
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
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix",
                                "unauth_action": "auth",
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



=== TEST 10: The value of redirect_uri should be appended to `.apisix/redirect` in the original request.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local redirect_uri = uri .. "/.apisix/redirect"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=' .. redirect_uri) ~= -1 then
                ngx.say(true)
            end
        }
    }
--- timeout: 10s
--- response_body
true
--- error_code: 302



=== TEST 11: Set up route with plugin matching  URI `/*` and point plugin to local Keycloak instance and set claim validator.
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
                                "claim_schema": {
                                    "type": "object",
                                    "properties": {
                                        "access_token": { "type" : "string"},
                                        "id_token": { "type" : "object"},
                                        "user": { "type" : "object"}
                                    },
                                    "required" : ["access_token","id_token","user"]
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



=== TEST 12: Access route w/o bearer token and go through the full OIDC Relying Party authentication process and validate claim successfully.
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



=== TEST 13: Set up route with plugin matching  URI `/*` and point plugin to local Keycloak instance and set claim validator with more strict schema.
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
                                "claim_schema": {
                                    "type": "object",
                                    "properties": {
                                        "access_token": { "type" : "string"},
                                        "id_token": { "type" : "object"},
                                        "user": { "type" : "object"},
                                        "user1": { "type" : "object"}
                                    },
                                    "required" : ["access_token","id_token","user","user1"]
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



=== TEST 14: Access route w/o bearer token and go through the full OIDC Relying Party authentication process and fail to validate claim.
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
            ngx.say('here error',err)
                -- No response, must be an error.
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 401
--- error_log
property "user1" is required

=== TEST 15: Set up route with plugin matching  URI `/*` and point plugin to local Keycloak instance and set invalid claim schema.
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
                                "claim_schema": {
                                    "type": "object",
                                    "properties": {
                                        "access_token": { "type" : "string"},
                                        "id_token": { "type" : "object"},
                                        "user": { "type" : "invalid_type"}
                                    },
                                    "required" : ["access_token","id_token","user"]
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
--- error_code: 400
--- response_body_like
{"error_msg":"failed to check the configuration of plugin openid-connect err: generate claim_schema validator failed: .*: invalid JSON type: invalid_type"}