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
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                match_var = "http_x_tenant_id",
                configs = {
                    {key = "acme", discovery = "a", client_id = "b", client_secret = "c"},
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: Missing `match_var`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                configs = {
                    {key = "acme", discovery = "a", client_id = "b", client_secret = "c"},
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
then clause did not match
done



=== TEST 3: Missing `configs`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                match_var = "http_x_tenant_id",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "configs" is required
done



=== TEST 4: A `configs` entry missing a required field is rejected.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                match_var = "http_x_tenant_id",
                configs = {
                    {key = "acme", discovery = "a", client_id = "b"},
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body_like
property "configs" validation failed:.*"client_secret" is required
done



=== TEST 5: rewrite() sets the oidc_* ctx vars when the match_var value hits a config.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_var = "http_x_tenant_id",
                configs = {
                    {key = "acme", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                    {key = "globex", discovery = "https://globex.example.com/.well-known/openid-configuration",
                     client_id = "globex-client", client_secret = "globex-secret"},
                }
            }
            local ctx = {var = {http_x_tenant_id = "globex"}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery)
            ngx.say(ctx.var.oidc_client_id)
            ngx.say(ctx.var.oidc_client_secret)
        }
    }
--- response_body
https://globex.example.com/.well-known/openid-configuration
globex-client
globex-secret



=== TEST 6: rewrite() sets nothing when the match_var value hits no config.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_var = "http_x_tenant_id",
                configs = {
                    {key = "acme", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                }
            }
            local ctx = {var = {http_x_tenant_id = "unknown-tenant"}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery == nil and "nil" or ctx.var.oidc_discovery)
            ngx.say(ctx.var.oidc_client_id == nil and "nil" or ctx.var.oidc_client_id)
            ngx.say(ctx.var.oidc_client_secret == nil and "nil" or ctx.var.oidc_client_secret)
        }
    }
--- response_body
nil
nil
nil



=== TEST 7: rewrite() sets nothing when match_var itself is absent from the request.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_var = "http_x_tenant_id",
                configs = {
                    {key = "acme", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                }
            }
            local ctx = {var = {}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery == nil and "nil" or ctx.var.oidc_discovery)
        }
    }
--- response_body
nil



=== TEST 8b: rewrite() does not crash when reading match_var raises (e.g. an unrecognized nginx var name).
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_var = "not_a_real_nginx_var",
                configs = {
                    {key = "acme", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                }
            }
            local var = setmetatable({}, {
                __index = function(_, key)
                    error("variable \"" .. key .. "\" not found")
                end
            })
            local ctx = {var = var}

            local ok, err = pcall(plugin.rewrite, conf, ctx)

            ngx.say(ok and "no crash" or ("crashed: " .. tostring(err)))
        }
    }
--- response_body
no crash
--- error_log
openid-connect-consumer-selector: failed to read var "not_a_real_nginx_var"



=== TEST 9: End to end - route with both plugins, unresolved tenant fails closed with 500 from openid-connect.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/oidc-selector-e2e',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect-consumer-selector": {
                                "match_var": "http_x_tenant_id",
                                "configs": [
                                    {
                                        "key": "acme",
                                        "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                        "client_id": "course_management",
                                        "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5"
                                    }
                                ]
                            },
                            "openid-connect": {
                                "discovery": "${oidc_discovery}",
                                "client_id": "${oidc_client_id}",
                                "client_secret": "${oidc_client_secret}",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
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
                        "uri": "/oidc-selector-e2e/*"
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



=== TEST 10: hitting the route from TEST 8 with an unrecognized tenant header fails closed with 500.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/oidc-selector-e2e/uri"
            local res, err = httpc:request_uri(uri, {method = "GET",
                headers = {["X-Tenant-Id"] = "not-a-real-tenant"}})
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- error_log
openid-connect: resolved value of "discovery" is empty
--- error_code: 500



=== TEST 11: match_source "token_iss" does not require match_var.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                match_source = "token_iss",
                configs = {
                    {key = "acme", discovery = "a", client_id = "b", client_secret = "c"},
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 12: default match_source ("var") still requires match_var.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local ok, err = plugin.check_schema({
                configs = {
                    {key = "acme", discovery = "a", client_id = "b", client_secret = "c"},
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
then clause did not match
done



=== TEST 13: rewrite() in "token_iss" mode selects the config matching the bearer token's "iss" claim.
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_source = "token_iss",
                configs = {
                    {key = "https://issuer-acme.example.com", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                    {key = "https://issuer-globex.example.com", discovery = "https://globex.example.com/.well-known/openid-configuration",
                     client_id = "globex-client", client_secret = "globex-secret"},
                }
            }

            local token = jwt:sign("test-signing-key-not-verified", {
                header = {typ = "JWT", alg = "HS256"},
                payload = {iss = "https://issuer-globex.example.com"},
            })

            ngx.req.set_header("Authorization", "Bearer " .. token)
            local ctx = {var = {}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery)
            ngx.say(ctx.var.oidc_client_id)
            ngx.say(ctx.var.oidc_client_secret)
        }
    }
--- response_body
https://globex.example.com/.well-known/openid-configuration
globex-client
globex-secret



=== TEST 14: rewrite() in "token_iss" mode sets nothing when there is no bearer token.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_source = "token_iss",
                configs = {
                    {key = "https://issuer-acme.example.com", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                }
            }
            local ctx = {var = {}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery == nil and "nil" or ctx.var.oidc_discovery)
        }
    }
--- response_body
nil



=== TEST 15: rewrite() in "token_iss" mode sets nothing when the bearer token's issuer matches no config.
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local plugin = require("apisix.plugins.openid-connect-consumer-selector")
            local conf = {
                match_source = "token_iss",
                configs = {
                    {key = "https://issuer-acme.example.com", discovery = "https://acme.example.com/.well-known/openid-configuration",
                     client_id = "acme-client", client_secret = "acme-secret"},
                }
            }

            local token = jwt:sign("test-signing-key-not-verified", {
                header = {typ = "JWT", alg = "HS256"},
                payload = {iss = "https://issuer-unknown.example.com"},
            })

            ngx.req.set_header("Authorization", "Bearer " .. token)
            local ctx = {var = {}}

            plugin.rewrite(conf, ctx)

            ngx.say(ctx.var.oidc_discovery == nil and "nil" or ctx.var.oidc_discovery)
        }
    }
--- response_body
nil



=== TEST 16: route with both plugins, matching on the "uri" var instead of a header.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/oidc-selector-e2e-uri-match',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect-consumer-selector": {
                                "match_var": "uri",
                                "configs": [
                                    {
                                        "key": "/oidc-selector-e2e-uri-match/uri",
                                        "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                        "client_id": "course_management",
                                        "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5"
                                    }
                                ]
                            },
                            "openid-connect": {
                                "discovery": "${oidc_discovery}",
                                "client_id": "${oidc_client_id}",
                                "client_secret": "${oidc_client_secret}",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
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
                        "uri": "/oidc-selector-e2e-uri-match/*"
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



=== TEST 17: hitting the route from TEST 15 at the matching URI authenticates through the selected config.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/oidc-selector-e2e-uri-match/uri"
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

            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- response_body_like
uri: /oidc-selector-e2e-uri-match/uri
cookie: .*



=== TEST 18: configs[].client_secret is encrypted at rest, not stored as the plaintext value set in TEST 8.
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/oidc-selector-e2e'))
            local conf = res.body.node.value.plugins["openid-connect-consumer-selector"]
            local stored_secret = conf.configs[1].client_secret

            ngx.say(type(stored_secret) == "string"
                    and stored_secret ~= "d1ec69e9-55d2-4109-a3ea-befa071579d5")
        }
    }
--- response_body
true
