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
                    name = "forwards revocation cache ttls",
                    session = {
                        secret = secret,
                        revocation = "redis",
                        redis = { host = "127.0.0.1" },
                        revocation_fail_mode = "closed",
                        revocation_cache_ttl = 5,
                        revocation_error_cache_ttl = 1,
                    },
                    check = function(opts)
                        assert(opts.revocation_cache_ttl == 5)
                        assert(opts.revocation_error_cache_ttl == 1)
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



=== TEST 4: logout revokes the presented cookie and the cookie of a refresh, even when the session is due for a rolling refresh
--- timeout: 30
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
                                "rolling_timeout": 8,
                                "revocation": "redis",
                                "revocation_fail_mode": "closed",
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "prefix": "oidc:revocation:rolling:"
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

            -- past 75% of rolling_timeout, where opening the session with
            -- start() would save it under a new session id
            ngx.sleep(7)

            -- this request refreshes the session, so it hands out a cookie
            -- with a new session id
            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("refreshing request failed: ", res and res.status or err)
                return
            end
            local refreshed_cookie = keycloak.concatenate_cookies(res.headers["Set-Cookie"])

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

            local replayed = res.status

            -- the cookie issued by the refresh belongs to the same login
            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = refreshed_cookie },
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            ngx.say("replayed=", replayed, " refreshed=", res.status)
        }
    }
--- response_body
replayed=302 refreshed=302



=== TEST 5: a fail-open store error is not replayed to a fail-closed configuration
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local keycloak = require("lib.keycloak")
            local test_admin = require("lib.test_admin").test

            -- nothing listens on port 1, so every revocation lookup fails
            local function put_route(fail_mode)
                return test_admin("/apisix/admin/routes/1",
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
                                    "revocation_fail_mode": "]] .. fail_mode .. [[",
                                    "redis": {
                                        "host": "127.0.0.1",
                                        "port": 1
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
            end

            local code, body = put_route("open")
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

            -- the cache is per worker, so replay enough times to reach all of them
            local function replay()
                local seen = {}
                for _ = 1, 10 do
                    local res, err = httpc:request_uri(uri, {
                        method = "GET",
                        headers = { Cookie = cookie },
                    })
                    if not res then
                        return "error: " .. tostring(err)
                    end
                    seen[res.status] = true
                end
                local statuses = {}
                for status in pairs(seen) do
                    statuses[#statuses + 1] = status
                end
                table.sort(statuses)
                return table.concat(statuses, ",")
            end

            ngx.say("open=", replay())

            -- same cookie name and secret, now rejecting on store errors
            code, body = put_route("closed")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            ngx.say("closed=", replay())
        }
    }
--- response_body
open=200
closed=503
--- error_log
OIDC session revocation store unavailable



=== TEST 6: a logout that fails on a Redis write can be retried with the same cookie
--- timeout: 40
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local redis = require("resty.redis")
            local keycloak = require("lib.keycloak")
            local test_admin = require("lib.test_admin").test

            local prefix = "oidc:revocation:retry:"
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
                                "rolling_timeout": 8,
                                "revocation": "redis",
                                "revocation_fail_mode": "closed",
                                "revocation_cache_ttl": 0,
                                "revocation_error_cache_ttl": 0,
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "prefix": "]] .. prefix .. [["
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

            local red = redis:new()
            red:set_timeout(1000)
            assert(red:connect("127.0.0.1", 6379))
            local function marks()
                return #assert(red:keys(prefix .. "*"))
            end
            -- a Redis that is over its memory limit still answers reads but
            -- rejects writes
            local function writes(allowed)
                assert(red:config("set", "maxmemory", allowed and 0 or 1))
            end
            writes(true)

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

            -- past 75% of rolling_timeout, where a request refreshes the
            -- session and hands out a cookie with a new session id
            ngx.sleep(7)
            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res or res.status ~= 200 then
                ngx.status = 500
                ngx.say("refreshing request failed: ", res and res.status or err)
                return
            end
            local refreshed_cookie = keycloak.concatenate_cookies(res.headers["Set-Cookie"])

            -- two distinct cookies of one login, both valid
            for _, c in ipairs({ cookie, refreshed_cookie }) do
                res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { Cookie = c },
                })
                if not res or res.status ~= 200 then
                    writes(true)
                    ngx.status = 500
                    ngx.say("cookie rejected before logout: ", res and res.status or err)
                    return
                end
            end
            assert(cookie ~= refreshed_cookie)

            local logout_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"

            -- the first logout cannot write its marks
            writes(false)
            res, err = httpc:request_uri(logout_uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            writes(true)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local first_status = res.status
            local cookie_cleared = res.headers["Set-Cookie"] ~= nil
            local marks_after_failure = marks()

            -- the browser kept its cookie, so it sends the logout again
            res, err = httpc:request_uri(logout_uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            local retry_status = res.status

            -- both cookies would still be valid if the retry had not revoked them
            local statuses = {}
            for _, c in ipairs({ cookie, refreshed_cookie }) do
                res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { Cookie = c },
                })
                if not res then
                    ngx.status = 500
                    ngx.say(err)
                    return
                end
                statuses[#statuses + 1] = res.status
            end

            ngx.say("first=", first_status, " cleared=", tostring(cookie_cleared),
                    " marks_after_failure=", marks_after_failure,
                    " retry=", retry_status,
                    " marks_after_retry_ok=", tostring(marks() >= 2),
                    " cookie=", statuses[1], " refreshed=", statuses[2])
        }
    }
--- response_body
first=503 cleared=false marks_after_failure=0 retry=302 marks_after_retry_ok=true cookie=302 refreshed=302
--- error_log
failed to destroy session



=== TEST 7: a logout that wrote the lineage mark but not the session id mark can be retried
--- timeout: 40
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local redis = require("resty.redis")
            local keycloak = require("lib.keycloak")
            local test_admin = require("lib.test_admin").test

            -- resty.redis has no ACL commands, so send them as raw RESP
            local function acl(...)
                local args = { "ACL", ... }
                local parts = { "*" .. #args .. "\r\n" }
                for _, arg in ipairs(args) do
                    parts[#parts + 1] = "$" .. #arg .. "\r\n" .. arg .. "\r\n"
                end
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", 6379))
                assert(sock:send(table.concat(parts)))
                local line = assert(sock:receive("*l"))
                sock:close()
                return line
            end

            -- keys are "<prefix>:<cookie name>:<base64url of the mark key>", and the
            -- mark keys of a lineage start with "lineage:", "bGluZWFnZT" encoded.
            -- The next character depends on the first one of the lineage ID: "o"
            -- for digits and "-", "p" for letters and "_".
            local prefix = "oidc:revocation:partial:"
            local lineage_keys = prefix .. ":session:bGluZWFnZT[op]*"
            acl("DELUSER", "partial")
            -- this user reads everything but may only write lineage marks
            assert(acl("SETUSER", "partial", "on", ">partialpw", "+@all", "%R~*",
                       "%W~" .. lineage_keys) == "+OK")

            -- the pattern has to allow the mark of any lineage ID, whichever
            -- character it starts with, and keep denying the session id marks
            local function mark_key(id)
                local encoded = ngx.encode_base64("lineage:" .. id)
                encoded = encoded:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
                return prefix .. ":session:" .. encoded
            end
            for _, id in ipairs({ "Abc", "zbc", "0bc", "9bc", "-bc", "_bc" }) do
                assert(acl("DRYRUN", "partial", "SET", mark_key(id), "1") == "+OK",
                       "lineage mark of an ID starting with " .. id:sub(1, 1) .. " is denied")
            end
            assert(acl("DRYRUN", "partial", "SET", prefix .. ":session:c2lkLW1hcms", "1")
                       :sub(1, 1) == "$", "session id marks must be denied")

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
                                "rolling_timeout": 8,
                                "revocation": "redis",
                                "revocation_fail_mode": "closed",
                                "revocation_cache_ttl": 0,
                                "revocation_error_cache_ttl": 0,
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "username": "partial",
                                    "password": "partialpw",
                                    "prefix": "]] .. prefix .. [["
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
                acl("DELUSER", "partial")
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local red = redis:new()
            red:set_timeout(1000)
            assert(red:connect("127.0.0.1", 6379))
            local function marks(pattern)
                return #assert(red:keys(pattern))
            end

            local function fail(...)
                acl("DELUSER", "partial")
                ngx.status = 500
                ngx.say(...)
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = keycloak.login_keycloak(
                uri, "teacher@gmail.com", "123456")
            if err then
                return fail(err)
            end

            local cookie = keycloak.concatenate_cookies(res.headers["Set-Cookie"])
            local httpc = http.new()

            -- past 75% of rolling_timeout, where a request refreshes the
            -- session and hands out a cookie with a new session id
            ngx.sleep(7)
            res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res or res.status ~= 200 then
                return fail("refreshing request failed: ", res and res.status or err)
            end
            local refreshed_cookie = keycloak.concatenate_cookies(res.headers["Set-Cookie"])
            assert(cookie ~= refreshed_cookie)

            for _, c in ipairs({ cookie, refreshed_cookie }) do
                res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { Cookie = c },
                })
                if not res or res.status ~= 200 then
                    return fail("cookie rejected before logout: ", res and res.status or err)
                end
            end

            -- the first logout writes the lineage mark and is refused the other one
            local logout_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/logout"
            res, err = httpc:request_uri(logout_uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res then
                return fail(err)
            end
            local first_status = res.status
            local cookie_cleared = res.headers["Set-Cookie"] ~= nil
            local lineage_marks = marks(lineage_keys)
            local sid_marks = marks(prefix .. "*") - lineage_marks

            -- writes are allowed again; the browser sends the logout once more
            assert(acl("SETUSER", "partial", "%W~*") == "+OK")
            res, err = httpc:request_uri(logout_uri, {
                method = "GET",
                headers = { Cookie = cookie },
            })
            if not res then
                return fail(err)
            end
            local retry_status = res.status

            -- both cookies would still be valid if the retry had not revoked them
            local statuses = {}
            for _, c in ipairs({ cookie, refreshed_cookie }) do
                res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { Cookie = c },
                })
                if not res then
                    return fail(err)
                end
                statuses[#statuses + 1] = res.status
            end

            acl("DELUSER", "partial")
            ngx.say("first=", first_status, " cleared=", tostring(cookie_cleared),
                    " lineage_marks=", lineage_marks, " sid_marks=", sid_marks,
                    " retry=", retry_status,
                    " cookie=", statuses[1], " refreshed=", statuses[2])
        }
    }
--- response_body
first=503 cleared=false lineage_marks=1 sid_marks=0 retry=302 cookie=302 refreshed=302
--- error_log
failed to destroy session
