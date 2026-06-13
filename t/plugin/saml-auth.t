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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = $block->extra_yaml_config // '';
    $extra_yaml_config .= <<_EOC_;
plugins:
  - saml-auth                      # priority: 2598
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->error_log_like) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema validation - valid config with all required fields
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: schema validation - missing required field sp_issuer
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body_like eval
qr/failed: .*sp_issuer.*is required/



=== TEST 3: schema validation - missing required field idp_uri
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body_like eval
qr/failed: .*idp_uri.*is required/



=== TEST 4: schema validation - invalid auth_protocol_binding_method
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
                auth_protocol_binding_method = "HTTP-INVALID",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body_like eval
qr/failed: .*auth_protocol_binding_method/



=== TEST 5: schema validation - missing required field secret
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body_like eval
qr/failed: .*secret.*is required/



=== TEST 6: schema validation - secret too short (< 8 chars)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "short",
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body_like eval
qr/failed: .*secret/



=== TEST 7: schema validation - valid config with optional fields
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.saml-auth")
            local ok, err = plugin.check_schema({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                auth_protocol_binding_method = "HTTP-POST",
                secret = "mysecret1",
                secret_fallbacks = {"oldsecret1", "oldsecret2"},
            })
            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: rewrite sets ctx.external_user when saml:authenticate succeeds
--- config
    location /t {
        content_by_lua_block {
            local old_plugin = package.loaded["apisix.plugins.saml-auth"]
            local old_saml = package.loaded["resty.saml"]

            package.loaded["apisix.plugins.saml-auth"] = nil
            package.loaded["resty.saml"] = nil

            local mock_user = "testuser@example.com"
            local mock_saml_obj = {}
            function mock_saml_obj:authenticate()
                return mock_user
            end
            package.loaded["resty.saml"] = {
                init = function(opts) return nil end,
                new = function(conf) return mock_saml_obj end,
            }

            local plugin = require("apisix.plugins.saml-auth")
            local ctx = {conf_type = "route", conf_id = "test-saml", conf_version = 1}
            plugin.rewrite({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
            }, ctx)

            package.loaded["apisix.plugins.saml-auth"] = old_plugin
            package.loaded["resty.saml"] = old_saml

            ngx.say(ctx.external_user)
        }
    }
--- response_body
testuser@example.com



=== TEST 9: rewrite returns 500 when saml:authenticate fails
--- config
    location /t {
        content_by_lua_block {
            local old_plugin = package.loaded["apisix.plugins.saml-auth"]
            local old_saml = package.loaded["resty.saml"]

            package.loaded["apisix.plugins.saml-auth"] = nil
            package.loaded["resty.saml"] = nil

            local mock_saml_obj = {}
            function mock_saml_obj:authenticate()
                return nil, "mock auth error"
            end
            package.loaded["resty.saml"] = {
                init = function(opts) return nil end,
                new = function(conf) return mock_saml_obj end,
            }

            local plugin = require("apisix.plugins.saml-auth")
            local code, body = plugin.rewrite({
                sp_issuer = "https://sp.example.com",
                idp_uri = "https://idp.example.com/sso",
                idp_cert = "MIIC...",
                login_callback_uri = "https://sp.example.com/login/callback",
                logout_uri = "https://sp.example.com/logout",
                logout_callback_uri = "https://sp.example.com/logout/callback",
                logout_redirect_uri = "https://sp.example.com/logout/done",
                sp_cert = "MIIC...",
                sp_private_key = "MIIE...",
                secret = "mysecret1",
            }, {conf_type = "route", conf_id = "test-saml", conf_version = 1})

            package.loaded["apisix.plugins.saml-auth"] = old_plugin
            package.loaded["resty.saml"] = old_saml

            ngx.say(code)
            ngx.say(body.message)
        }
    }
--- response_body
500
saml authentication failed
--- no_error_log
[crit]
--- error_log_like eval
qr/saml authenticate failed: mock auth error/



=== TEST 10: (integration) add route for sp1
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            opts.sp_issuer = "sp"
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "host" : "127.0.0.1",
                        "plugins": {
                            "saml-auth": ]] .. core.json.encode(opts) .. [[
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



=== TEST 11: (integration) login and logout ok
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_saml"

            local path = "/uri"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, saml_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = saml_cookie
                }
            })
            assert(res.status == 200)
            ngx.say(res.body)

            res, err = kc.logout_keycloak(uri .. "/logout", saml_cookie, keycloak_cookie)
            if err or res.headers['Location'] ~= "/logout_ok" then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
        }
    }
--- response_body_like
uri: /uri
cookie: .*
host: 127.0.0.1:1984
user-agent: .*
x-real-ip: 127.0.0.1
--- error_log
login callback req with redirect



=== TEST 12: (integration) add route for sp2
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            opts.sp_issuer = "sp2"
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "host" : "127.0.0.2",
                        "plugins": {
                            "saml-auth": ]] .. core.json.encode(opts) .. [[
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



=== TEST 13: (integration) login sp1 and sp2, then do single logout
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_saml"

            local path = "/uri"

            -- login to sp1
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, saml_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = saml_cookie
                }
            })
            assert(res.status == 200)

            -- login to sp2, which would skip login at keycloak side
            local uri2 = "http://127.0.0.2:" .. ngx.var.server_port

            local res, err, saml_cookie2 = kc.login_keycloak_for_second_sp(uri2 .. path, keycloak_cookie)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri2 .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = saml_cookie2
                }
            })
            assert(res.status == 200)

            -- SLO (single logout)
            res, err = kc.single_logout(uri .. "/logout", saml_cookie, saml_cookie2, keycloak_cookie)
            if err or res.headers['Location'] ~= "/logout_ok" then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end

            -- login to sp2, which would do normal login process at keycloak side
            local res, err, saml_cookie2, keycloak_cookie = kc.login_keycloak(uri2 .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = saml_cookie2
                }
            })
            assert(res.status == 200)

            -- logout sp2
            res, err = kc.logout_keycloak(uri2 .. "/logout", saml_cookie2, keycloak_cookie)
            if err or res.headers['Location'] ~= "/logout_ok" then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
        }
    }
--- error_log
login callback req with redirect



=== TEST 14: (integration) add route for sp1 with wrong login_callback_uri
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            opts.sp_issuer = "sp"
            opts.login_callback_uri = "/wrong_url"
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "host" : "127.0.0.1",
                        "plugins": {
                            "saml-auth": ]] .. core.json.encode(opts) .. [[
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



=== TEST 15: (integration) login failed
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_saml"

            local path = "/uri"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res = kc.login_keycloak(uri .. path, username, password)
            assert(res == nil)
        }
    }
