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

=== TEST 1: cookie session is revoked after logout
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local keycloak = require("lib.keycloak")
            local test_admin = require("lib.test_admin").test

            local code, body = test_admin("/apisix/admin/routes/1",
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "openid-connect": {
                            "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                            "realm": "University",
                            "client_id": "course_management",
                            "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                            "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port
                                .. [[/authenticated",
                            "ssl_verify": false,
                            "session": {
                                "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                "storage": "cookie",
                                "revocation": "redis",
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "prefix": "oidc:revocation:"
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
                    "uri": "/*"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = keycloak.login_keycloak(
                uri, "teacher@gmail.com", "123456")
            if err then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local cookie = keycloak.concatenate_cookies(res.headers["Set-Cookie"])
            local httpc = http.new()

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("authenticated request failed: ",
                        res and res.status or err)
                return
            end

            local logout_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            res, err = httpc:request_uri(logout_uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res or res.status ~= 302 then
                ngx.status = 500
                ngx.say("logout failed: ", res and res.status or err)
                return
            end

            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            if res.status ~= 302 then
                ngx.status = 500
                ngx.say("replayed request was not redirected: ", res.status)
                return
            end

            ngx.say("authenticated=", 200)
            ngx.say("replayed=", res.status)
        }
    }
--- response_body
authenticated=200
replayed=302



=== TEST 2: forwarded and optional session revocation paths
--- config
    location /t {
        content_by_lua_block {
            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local test_cases = {
                {
                    name = "revocation uses library fail-open default",
                    session = {
                        secret = secret,
                        storage = "cookie",
                        revocation = "redis",
                        redis = {
                            host = "127.0.0.1",
                            prefix = "oidc:session:",
                        },
                    },
                    check = function(opts)
                        assert(opts.revocation == "redis")
                        assert(opts.revocation_fail_mode == nil)
                        assert(opts.redis.host == "127.0.0.1")
                        assert(opts.redis.prefix == "oidc:session:")
                    end,
                },
                {
                    name = "explicit fail open",
                    session = {
                        secret = secret,
                        revocation = "redis",
                        redis = { host = "127.0.0.1" },
                        revocation_fail_mode = "open",
                    },
                    check = function(opts)
                        assert(opts.revocation == "redis")
                        assert(opts.revocation_fail_mode == "open")
                    end,
                },
                {
                    name = "fail closed with default cookie storage",
                    session = {
                        secret = secret,
                        revocation = "redis",
                        redis = { host = "127.0.0.1" },
                        revocation_fail_mode = "closed",
                    },
                    check = function(opts)
                        assert(opts.revocation == "redis")
                        assert(opts.revocation_fail_mode == "closed")
                    end,
                },
                {
                    name = "omitting revocation leaves it disabled",
                    session = {
                        secret = secret,
                        storage = "cookie",
                        redis = { host = "127.0.0.1" },
                    },
                    check = function(opts)
                        assert(opts.revocation == nil)
                        assert(opts.revocation_fail_mode == nil)
                    end,
                },
                {
                    name = "redis session storage remains unchanged",
                    session = {
                        secret = secret,
                        storage = "redis",
                        redis = { host = "127.0.0.1" },
                    },
                    check = function(opts)
                        assert(opts.storage == "redis")
                        assert(opts.revocation == nil)
                        assert(opts.revocation_fail_mode == nil)
                        assert(opts.redis.host == "127.0.0.1")
                    end,
                },
            }

            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "c",
                    session = case.session,
                })
                assert(ok, case.name .. ": " .. tostring(err))
                case.check(plugin._build_session_opts(case.session))
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: session revocation schema failure paths
--- config
    location /t {
        content_by_lua_block {
            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local test_cases = {
                {
                    name = "invalid revocation backend",
                    session = {
                        secret = secret,
                        revocation = "invalid",
                        redis = { host = "127.0.0.1" },
                    },
                    error_field = "revocation",
                },
                {
                    name = "invalid fail mode",
                    session = {
                        secret = secret,
                        revocation = "redis",
                        redis = { host = "127.0.0.1" },
                        revocation_fail_mode = "invalid",
                    },
                    error_field = "revocation_fail_mode",
                },
                {
                    name = "missing redis",
                    session = {
                        secret = secret,
                        revocation = "redis",
                    },
                    error_field = "allOf",
                },
                {
                    name = "redis session storage",
                    session = {
                        secret = secret,
                        storage = "redis",
                        revocation = "redis",
                        redis = { host = "127.0.0.1" },
                    },
                    error_field = "allOf",
                },
            }

            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema({
                    client_id = "a",
                    client_secret = "b",
                    discovery = "c",
                    session = case.session,
                })
                assert(not ok, case.name)
                assert(string.find(err, case.error_field, 1, true),
                       case.name .. ": " .. tostring(err))
            end

            ngx.say("done")
        }
    }
--- response_body
done
