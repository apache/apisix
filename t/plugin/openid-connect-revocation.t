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

=== TEST 1: valid session with cookie storage and redis revocation denylist
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                    redis = {
                        host = "redis",
                        mode = "revocation",
                        prefix = "oidc:session:",
                    },
                    revocation_fail_mode = "open",
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 2: build_session_opts passes redis mode through for revocation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                redis = {
                    host = "redis",
                    mode = "revocation",
                    prefix = "oidc:session:",
                },
                revocation_fail_mode = "open",
            })
            ngx.say("storage=", tostring(opts.storage))
            ngx.say("redis.host=", opts.redis.host)
            ngx.say("redis.mode=", tostring(opts.redis.mode))
            ngx.say("revocation_fail_mode=", opts.revocation_fail_mode)
        }
    }
--- response_body
storage=cookie
redis.host=redis
redis.mode=revocation
revocation_fail_mode=open



=== TEST 3: build_session_opts passes redis mode through for session storage
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "redis",
                redis = {
                    host = "127.0.0.1",
                    port = 6379,
                    mode = "storage",
                },
            })
            ngx.say("storage=", opts.storage)
            ngx.say("redis.host=", opts.redis.host)
            ngx.say("redis.mode=", tostring(opts.redis.mode))
        }
    }
--- response_body
storage=redis
redis.host=127.0.0.1
redis.mode=storage



=== TEST 4: session.revocation is rejected (use session.redis instead)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    revocation = {
                        redis = { host = "127.0.0.1" },
                    },
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body_like
.*additional properties forbidden.*revocation.*



=== TEST 5: invalid revocation_fail_mode value is rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                    redis = {
                        host = "127.0.0.1",
                        mode = "revocation",
                    },
                    revocation_fail_mode = "bogus",
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body_like
.*revocation_fail_mode.*



=== TEST 6: build_session_opts passes revocation_fail_mode closed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "closed",
            })
            ngx.say("revocation_fail_mode=", opts.revocation_fail_mode)
            ngx.say("storage=", tostring(opts.storage))
        }
    }
--- response_body
revocation_fail_mode=closed
storage=cookie



=== TEST 7: valid schema with revocation_fail_mode closed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                    redis = {
                        host = "127.0.0.1",
                        mode = "revocation",
                    },
                    revocation_fail_mode = "closed",
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 8: redis.mode defaults to revocation when storage is cookie
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                    redis = {
                        host = "127.0.0.1",
                    },
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 9: redis.mode defaults to storage when storage is redis
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        host = "127.0.0.1",
                        port = 6379,
                    },
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 10: cookie session without redis block is valid
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 11: fail closed rejects open when revocation check fails
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local session = require("resty.session")
            local build = plugin._build_session_opts

            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local cookie_name = "oidc_revocation_test"

            local function extract_cookie(raw)
                if type(raw) == "table" then
                    for _, v in ipairs(raw) do
                        local m = ngx.re.match(v, cookie_name .. "=([\\w-]+);")
                        if m then
                            return m[1]
                        end
                    end
                    return ""
                end
                local m = ngx.re.match(raw, cookie_name .. "=([\\w-]+);")
                return m and m[1] or ""
            end

            session.init({
                secret = secret,
                cookie_name = cookie_name,
            })
            local probe = session.new({ revocation_fail_mode = "open" })
            if probe.revocation_fail_mode == nil then
                ngx.say("skip: revocation not supported")
                return
            end

            local cookies = {}
            session.__set_ngx_header(cookies)
            local s = session.new()
            s:set("test_key", "test_data")
            local ok, err = s:save()
            if not ok then
                ngx.say("save failed: ", err)
                return
            end
            local session_cookie = extract_cookie(cookies["Set-Cookie"])
            s:close()

            local opts = build({
                secret = secret,
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "closed",
            })

            local s2 = session.new({
                secret = opts.secret,
                cookie_name = cookie_name,
                revocation_fail_mode = opts.revocation_fail_mode,
                revocation = {
                    set = function()
                        return true
                    end,
                    get = function()
                        return nil, "connection refused"
                    end,
                },
            })
            session.__set_ngx_var({
                ["cookie_" .. cookie_name] = session_cookie,
            })

            ok, err = s2:open()
            if ok then
                ngx.say("unexpected open success")
            else
                ngx.say(err)
            end
        }
    }
--- response_body eval
qr/^(skip: revocation not supported|unable to check session revocation)$/



=== TEST 12: fail open allows open when revocation check fails
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local session = require("resty.session")
            local build = plugin._build_session_opts

            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local cookie_name = "oidc_revocation_test"

            local function extract_cookie(raw)
                if type(raw) == "table" then
                    for _, v in ipairs(raw) do
                        local m = ngx.re.match(v, cookie_name .. "=([\\w-]+);")
                        if m then
                            return m[1]
                        end
                    end
                    return ""
                end
                local m = ngx.re.match(raw, cookie_name .. "=([\\w-]+);")
                return m and m[1] or ""
            end

            session.init({
                secret = secret,
                cookie_name = cookie_name,
            })
            local probe = session.new({ revocation_fail_mode = "open" })
            if probe.revocation_fail_mode == nil then
                ngx.say("skip: revocation not supported")
                return
            end

            local cookies = {}
            session.__set_ngx_header(cookies)
            local s = session.new()
            s:set("test_key", "test_data")
            local ok, err = s:save()
            if not ok then
                ngx.say("save failed: ", err)
                return
            end
            local session_cookie = extract_cookie(cookies["Set-Cookie"])
            s:close()

            local opts = build({
                secret = secret,
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "open",
            })

            local s2 = session.new({
                secret = opts.secret,
                cookie_name = cookie_name,
                revocation_fail_mode = opts.revocation_fail_mode,
                revocation = {
                    set = function()
                        return true
                    end,
                    get = function()
                        return nil, "connection refused"
                    end,
                },
            })
            session.__set_ngx_var({
                ["cookie_" .. cookie_name] = session_cookie,
            })

            ok, err = s2:open()
            if not ok then
                ngx.say("open failed: ", err)
                return
            end
            ngx.say("value=", s2:get("test_key"))
            s2:close()
        }
    }
--- response_body eval
qr/^(skip: revocation not supported|value=test_data)$/



=== TEST 13: fail closed rejects destroy when revocation mark fails
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local session = require("resty.session")
            local build = plugin._build_session_opts

            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local cookie_name = "oidc_revocation_test"

            local function extract_cookie(raw)
                if type(raw) == "table" then
                    for _, v in ipairs(raw) do
                        local m = ngx.re.match(v, cookie_name .. "=([\\w-]+);")
                        if m then
                            return m[1]
                        end
                    end
                    return ""
                end
                local m = ngx.re.match(raw, cookie_name .. "=([\\w-]+);")
                return m and m[1] or ""
            end

            session.init({
                secret = secret,
                cookie_name = cookie_name,
            })
            local probe = session.new({ revocation_fail_mode = "open" })
            if probe.revocation_fail_mode == nil then
                ngx.say("skip: revocation not supported")
                return
            end

            local cookies = {}
            session.__set_ngx_header(cookies)
            local s = session.new()
            s:set("test_key", "test_data")
            local ok, err = s:save()
            if not ok then
                ngx.say("save failed: ", err)
                return
            end
            local session_cookie = extract_cookie(cookies["Set-Cookie"])
            s:close()

            local opts = build({
                secret = secret,
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "closed",
            })

            local s2 = session.new({
                secret = opts.secret,
                cookie_name = cookie_name,
            })
            session.__set_ngx_var({
                ["cookie_" .. cookie_name] = session_cookie,
            })
            ok, err = s2:open()
            if not ok then
                ngx.say("open failed: ", err)
                return
            end

            s2.revocation = {
                set = function()
                    return nil, "connection refused"
                end,
                get = function()
                    return nil
                end,
            }
            s2.revocation_fail_mode = opts.revocation_fail_mode

            session.__set_ngx_header(cookies)
            ok, err = s2:destroy()
            if ok then
                ngx.say("unexpected destroy success")
            else
                ngx.say(err)
            end
        }
    }
--- response_body eval
qr/^(skip: revocation not supported|unable to mark session revoked)$/



=== TEST 14: fail open allows destroy when revocation mark fails
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local session = require("resty.session")
            local build = plugin._build_session_opts

            local secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
            local cookie_name = "oidc_revocation_test"

            local function extract_cookie(raw)
                if type(raw) == "table" then
                    for _, v in ipairs(raw) do
                        local m = ngx.re.match(v, cookie_name .. "=([\\w-]+);")
                        if m then
                            return m[1]
                        end
                    end
                    return ""
                end
                local m = ngx.re.match(raw, cookie_name .. "=([\\w-]+);")
                return m and m[1] or ""
            end

            session.init({
                secret = secret,
                cookie_name = cookie_name,
            })
            local probe = session.new({ revocation_fail_mode = "open" })
            if probe.revocation_fail_mode == nil then
                ngx.say("skip: revocation not supported")
                return
            end

            local cookies = {}
            session.__set_ngx_header(cookies)
            local s = session.new()
            s:set("test_key", "test_data")
            local ok, err = s:save()
            if not ok then
                ngx.say("save failed: ", err)
                return
            end
            local session_cookie = extract_cookie(cookies["Set-Cookie"])
            s:close()

            local opts = build({
                secret = secret,
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "open",
            })

            local s2 = session.new({
                secret = opts.secret,
                cookie_name = cookie_name,
            })
            session.__set_ngx_var({
                ["cookie_" .. cookie_name] = session_cookie,
            })
            ok, err = s2:open()
            if not ok then
                ngx.say("open failed: ", err)
                return
            end

            s2.revocation = {
                set = function()
                    return nil, "connection refused"
                end,
                get = function()
                    return nil
                end,
            }
            s2.revocation_fail_mode = opts.revocation_fail_mode

            session.__set_ngx_header(cookies)
            ok, err = s2:destroy()
            if not ok then
                ngx.say("destroy failed: ", err)
            else
                ngx.say("destroy ok")
            end
        }
    }
--- response_body eval
qr/^(skip: revocation not supported|destroy ok)$/



=== TEST 15: build_session_opts forwards revocation_fail_mode to session.new
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local session = require("resty.session")
            local build = plugin._build_session_opts

            local probe = session.new({ revocation_fail_mode = "open" })
            if probe.revocation_fail_mode == nil then
                ngx.say("skip: revocation not supported")
                return
            end

            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                redis = {
                    host = "127.0.0.1",
                    mode = "revocation",
                },
                revocation_fail_mode = "closed",
            })

            local s = session.new(opts)
            ngx.say("revocation_fail_mode=", s.revocation_fail_mode)
            ngx.say("storage=", opts.storage)
            ngx.say("has_revocation=", tostring(s.revocation ~= nil))
        }
    }
--- response_body eval
qr/^(skip: revocation not supported|revocation_fail_mode=closed\nstorage=cookie\nhas_revocation=true)$/
