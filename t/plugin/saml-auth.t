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



=== TEST 5: schema validation - secret too short (< 8 chars)
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



=== TEST 6: schema validation - valid config with optional fields
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



=== TEST 7: schema validation works when lua-resty-saml is unavailable
--- config
    location /t {
        content_by_lua_block {
            local old_plugin = package.loaded["apisix.plugins.saml-auth"]
            local old_saml = package.loaded["resty.saml"]
            local old_preload = package.preload["resty.saml"]

            package.loaded["apisix.plugins.saml-auth"] = nil
            package.loaded["resty.saml"] = nil
            package.preload["resty.saml"] = function()
                error("mock missing resty.saml")
            end

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

            package.loaded["apisix.plugins.saml-auth"] = old_plugin
            package.loaded["resty.saml"] = old_saml
            package.preload["resty.saml"] = old_preload

            if not ok then
                ngx.say("failed: ", err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: rewrite fails gracefully when lua-resty-saml is unavailable
--- config
    location /t {
        content_by_lua_block {
            local old_plugin = package.loaded["apisix.plugins.saml-auth"]
            local old_saml = package.loaded["resty.saml"]
            local old_preload = package.preload["resty.saml"]

            package.loaded["apisix.plugins.saml-auth"] = nil
            package.loaded["resty.saml"] = nil
            package.preload["resty.saml"] = function()
                error("mock missing resty.saml")
            end

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
            }, {})

            package.loaded["apisix.plugins.saml-auth"] = old_plugin
            package.loaded["resty.saml"] = old_saml
            package.preload["resty.saml"] = old_preload

            ngx.say(code)
            ngx.say(body.message)
        }
    }
--- response_body
503
lua-resty-saml is required for saml-auth
--- error_log_like eval
qr/failed to load lua-resty-saml/



=== TEST 9: rewrite sets ctx.external_user when saml:authenticate succeeds
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
            }, ctx)

            package.loaded["apisix.plugins.saml-auth"] = old_plugin
            package.loaded["resty.saml"] = old_saml

            ngx.say(ctx.external_user)
        }
    }
--- response_body
testuser@example.com
