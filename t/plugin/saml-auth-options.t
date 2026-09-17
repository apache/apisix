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

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // '';
    $extra_yaml_config .= <<_EOC_;
plugins:
  - saml-auth                      # priority: 2598
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: add route with issuer, audience, clock skew and ACS URL pinned
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.idp_issuers = {"http://127.0.0.1:8087/realms/test"}
            opts.sp_audiences = {"sp"}
            opts.clock_skew = 30
            opts.sp_acs_url = "http://127.0.0.1:1984/acs"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 2: login and logout ok with the pinned options
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_saml"

            local path = "/uri"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local res, err, saml_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, "test", "test")
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end
            res = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {["Cookie"] = saml_cookie}
            })
            ngx.say(res.status)

            res, err = kc.logout_keycloak(uri .. "/logout", saml_cookie, keycloak_cookie)
            if err or res.headers['Location'] ~= "/logout_ok" then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end
        }
    }
--- response_body
200
--- error_log
login callback req with redirect



=== TEST 3: add route accepting another issuer only
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.idp_issuers = {"http://127.0.0.1:8087/realms/other"}
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 4: login from an issuer outside idp_issuers is refused
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local res = http.new():request_uri(acs, {
                method = "GET",
                headers = {["Cookie"] = sp_cookie}
            })
            ngx.say(res.status)
        }
    }
--- response_body
401
--- error_log
unexpected issuer in response from IdP: http://127.0.0.1:8087/realms/test



=== TEST 5: add route with an empty idp_issuers
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.idp_issuers = core.json.decode("[]")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 6: an empty idp_issuers accepts no issuer
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local res = http.new():request_uri(acs, {
                method = "GET",
                headers = {["Cookie"] = sp_cookie}
            })
            ngx.say(res.status)
        }
    }
--- response_body
401
--- error_log
unexpected issuer in response from IdP: http://127.0.0.1:8087/realms/test



=== TEST 7: add route answering another audience only
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.sp_audiences = {"other-sp"}
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 8: login restricted to an audience outside sp_audiences is refused
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local res = http.new():request_uri(acs, {
                method = "GET",
                headers = {["Cookie"] = sp_cookie}
            })
            ngx.say(res.status)
        }
    }
--- response_body
401
--- error_log
is restricted to sp



=== TEST 9: add route without sp_acs_url
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 10: without sp_acs_url, a callback reaching the gateway under another host is refused
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local res = http.new():request_uri(acs, {
                method = "GET",
                headers = {["Cookie"] = sp_cookie, ["Host"] = "gateway.internal"}
            })
            ngx.say(res.status)
        }
    }
--- response_body
401
--- error_log
response from IdP is addressed to http://127.0.0.1:1984/acs



=== TEST 11: add route with sp_acs_url naming the external ACS
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.sp_acs_url = "http://127.0.0.1:1984/acs"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 12: with sp_acs_url, login works while the gateway sees another host
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"
            local headers = {["Host"] = "gateway.internal"}

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test",
                                                                   headers)
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end
            ngx.say(acs:sub(1, #"http://127.0.0.1:1984/acs?"))

            local httpc = http.new()
            local res = httpc:request_uri(acs, {
                method = "GET",
                headers = {["Cookie"] = sp_cookie, ["Host"] = "gateway.internal"}
            })
            ngx.say(res.status, " ", res.headers["Location"])

            res = httpc:request_uri(uri .. "/uri", {
                method = "GET",
                headers = {
                    ["Cookie"] = kc.concatenate_cookies(res.headers["Set-Cookie"]),
                    ["Host"] = "gateway.internal",
                }
            })
            ngx.say(res.status)
        }
    }
--- response_body
http://127.0.0.1:1984/acs?
302 /uri
200



=== TEST 13: without replay_dict, the same response is accepted twice
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local httpc = http.new()
            for _ = 1, 2 do
                local res = httpc:request_uri(acs, {
                    method = "GET",
                    headers = {["Cookie"] = sp_cookie}
                })
                ngx.say(res.status)
            end
        }
    }
--- response_body
302
302



=== TEST 14: add route with replay_dict
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.replay_dict = "saml_replay"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 15: with replay_dict, the same response is refused the second time
--- http_config
    lua_shared_dict saml_replay 1m;
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local kc = require "lib.keycloak_saml"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local acs, err, sp_cookie = kc.login_keycloak_until_acs(uri .. "/uri", "test", "test")
            if not acs then
                ngx.log(ngx.ERR, err)
                return ngx.exit(500)
            end

            local httpc = http.new()
            for _ = 1, 2 do
                local res = httpc:request_uri(acs, {
                    method = "GET",
                    headers = {["Cookie"] = sp_cookie}
                })
                ngx.say(res.status)
            end
        }
    }
--- response_body
302
401
--- error_log
has been presented already



=== TEST 16: add route naming a lua_shared_dict that is not declared
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_saml")
            local core = require("apisix.core")

            local opts = core.table.deepcopy(kc.get_default_opts())
            opts.sp_issuer = "sp"
            opts.replay_dict = "undeclared_replay"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 17: a missing replay_dict fails the request
--- request
GET /uri
--- error_code: 500
--- response_body
{"message":"create saml object failed"}
--- error_log
no lua_shared_dict named undeclared_replay
