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

=== TEST 1: valid session with explicit cookie.name, cookie.path, cookie.lifetime
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
                    cookie = {
                        name = "my_session",
                        path = "/app",
                        lifetime = 7200,
                    }
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



=== TEST 2: valid session with pass-through additional cookie properties
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
                    cookie = {
                        name = "oidc_session",
                        cookie_secure = true,
                        cookie_same_site = "Strict",
                        idling_timeout = 600,
                        rolling_timeout = 1800,
                        remember = true,
                    }
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



=== TEST 3: backward-compatible cookie.lifetime still accepted
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
                    cookie = {
                        lifetime = 3600,
                    }
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



=== TEST 4: build_session_opts maps cookie.name/path/lifetime to flat keys
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                cookie = {
                    name = "my_session",
                    path = "/app",
                    lifetime = 7200,
                }
            })
            ngx.say("cookie_name=", opts.cookie_name)
            ngx.say("cookie_path=", opts.cookie_path)
            ngx.say("absolute_timeout=", opts.absolute_timeout)
            ngx.say("secret=", opts.secret)
            ngx.say("storage=", opts.storage)
            ngx.say("cookie=", tostring(opts.cookie))
        }
    }
--- response_body
cookie_name=my_session
cookie_path=/app
absolute_timeout=7200
secret=jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK
storage=cookie
cookie=nil



=== TEST 5: build_session_opts passes through additional cookie.* properties
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie = {
                    name = "sess",
                    cookie_secure = true,
                    cookie_same_site = "Strict",
                    idling_timeout = 600,
                }
            })
            ngx.say("cookie_name=", opts.cookie_name)
            ngx.say("cookie_secure=", tostring(opts.cookie_secure))
            ngx.say("cookie_same_site=", opts.cookie_same_site)
            ngx.say("idling_timeout=", opts.idling_timeout)
        }
    }
--- response_body
cookie_name=sess
cookie_secure=true
cookie_same_site=Strict
idling_timeout=600



=== TEST 6: build_session_opts returns nil for nil input
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            ngx.say(tostring(build(nil)))
        }
    }
--- response_body
nil



=== TEST 7: build_session_opts works when cookie field is absent
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "redis",
                redis = { host = "127.0.0.1", port = 6379 },
            })
            ngx.say("secret=", opts.secret)
            ngx.say("storage=", opts.storage)
            ngx.say("redis.host=", opts.redis.host)
            ngx.say("redis.port=", opts.redis.port)
        }
    }
--- response_body
secret=jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK
storage=redis
redis.host=127.0.0.1
redis.port=6379



=== TEST 8: invalid type for cookie.lifetime (string instead of integer)
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
                    cookie = {
                        lifetime = "invalid",
                    }
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
property "lifetime" validation failed: wrong type: expected integer, got string.*



=== TEST 9: invalid type for additional cookie property (array is rejected)
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
                    cookie = {
                        some_option = { "not", "allowed" },
                    }
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
failed to validate additional property some_option.*



=== TEST 10: valid session with redis storage and cookie overrides
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
                    cookie = {
                        name = "oidc_session",
                        lifetime = 7200,
                    }
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



=== TEST 11: explicit alias wins over conflicting pass-through key (lifetime vs absolute_timeout)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie = {
                    lifetime = 7200,
                    absolute_timeout = 1,
                }
            })
            ngx.say("absolute_timeout=", opts.absolute_timeout)
        }
    }
--- response_body
absolute_timeout=7200
--- error_log
session.cookie: both 'lifetime' and 'absolute_timeout' are set



=== TEST 12: explicit alias wins over conflicting pass-through key (name vs cookie_name)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie = {
                    name = "alias_wins",
                    cookie_name = "passthrough_loses",
                }
            })
            ngx.say("cookie_name=", opts.cookie_name)
        }
    }
--- response_body
cookie_name=alias_wins
--- error_log
session.cookie: both 'name' and 'cookie_name' are set



=== TEST 13: no warning when only the alias is set
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie = {
                    lifetime = 7200,
                }
            })
            ngx.say("absolute_timeout=", opts.absolute_timeout)
        }
    }
--- response_body
absolute_timeout=7200
--- no_error_log
session.cookie: both



=== TEST 14: no warning when only the pass-through key is set
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie = {
                    absolute_timeout = 1800,
                }
            })
            ngx.say("absolute_timeout=", opts.absolute_timeout)
        }
    }
--- response_body
absolute_timeout=1800
--- no_error_log
session.cookie: both
