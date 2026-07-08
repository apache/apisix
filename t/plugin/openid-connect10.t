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

=== TEST 1: valid session with flat cookie_name, cookie_path, absolute_timeout
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
                    cookie_name = "my_session",
                    cookie_path = "/app",
                    absolute_timeout = 7200,
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



=== TEST 2: valid session with flat cookie_secure, cookie_same_site, idling/rolling timeouts
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
                    cookie_name = "oidc_session",
                    cookie_secure = true,
                    cookie_http_only = true,
                    cookie_same_site = "Strict",
                    cookie_domain = "example.com",
                    idling_timeout = 600,
                    rolling_timeout = 1800,
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



=== TEST 3: backward-compatible session.cookie.lifetime still accepted
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



=== TEST 4: build_session_opts passes flat keys through untouched
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                cookie_name = "my_session",
                cookie_path = "/app",
                cookie_secure = true,
                cookie_same_site = "Strict",
                idling_timeout = 600,
                rolling_timeout = 1800,
                absolute_timeout = 7200,
            })
            ngx.say("cookie_name=", opts.cookie_name)
            ngx.say("cookie_path=", opts.cookie_path)
            ngx.say("cookie_secure=", tostring(opts.cookie_secure))
            ngx.say("cookie_same_site=", opts.cookie_same_site)
            ngx.say("idling_timeout=", opts.idling_timeout)
            ngx.say("rolling_timeout=", opts.rolling_timeout)
            ngx.say("absolute_timeout=", opts.absolute_timeout)
            ngx.say("storage=", opts.storage)
            ngx.say("cookie=", tostring(opts.cookie))
        }
    }
--- response_body
cookie_name=my_session
cookie_path=/app
cookie_secure=true
cookie_same_site=Strict
idling_timeout=600
rolling_timeout=1800
absolute_timeout=7200
storage=cookie
cookie=nil



=== TEST 5: build_session_opts maps deprecated cookie.lifetime to absolute_timeout
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
            ngx.say("cookie.lifetime=", opts.cookie.lifetime)
        }
    }
--- response_body
absolute_timeout=7200
cookie.lifetime=7200
--- error_log
session.cookie.lifetime is deprecated



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



=== TEST 9: valid session with redis storage and flat cookie options
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
                    cookie_name = "oidc_session",
                    absolute_timeout = 7200,
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



=== TEST 10: absolute_timeout wins when both it and cookie.lifetime are set
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                absolute_timeout = 1800,
                cookie = {
                    lifetime = 7200,
                }
            })
            ngx.say("absolute_timeout=", opts.absolute_timeout)
        }
    }
--- response_body
absolute_timeout=1800
--- no_error_log
session.cookie.lifetime is deprecated



=== TEST 11: unknown key directly under session is rejected
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
                    not_a_real_option = true,
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
.*additional properties forbidden.*not_a_real_option.*



=== TEST 12: invalid cookie_same_site value is rejected
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
                    cookie_same_site = "bogus",
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
.*cookie_same_site.*



=== TEST 13: sibling routes get distinct default session cookie names
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local derive = plugin._route_session_cookie_name
            local conf = { client_id = "shared" }
            local a = derive(conf, { route_id = "route-A" })
            local b = derive(conf, { route_id = "route-B" })
            ngx.say("distinct=", tostring(a ~= b))
            ngx.say("stable=", tostring(a == derive(conf, { route_id = "route-A" })))
            ngx.say("prefixed=", tostring(a:find("^session_") ~= nil))
        }
    }
--- response_body
distinct=true
stable=true
prefixed=true



=== TEST 14: cookie name falls back to client_id when no route id
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local derive = plugin._route_session_cookie_name
            local by_client = derive({ client_id = "the-client" }, nil)
            ngx.say("from_client=", tostring(by_client ~= nil))
            ngx.say("none=", tostring(derive({}, nil)))
        }
    }
--- response_body
from_client=true
none=nil



=== TEST 15: default cookie name is applied when session.cookie_name is unset
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
            }, "session_deadbeef")
            ngx.say("cookie_name=", opts.cookie_name)
        }
    }
--- response_body
cookie_name=session_deadbeef



=== TEST 16: operator-set cookie_name wins over the derived default
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                cookie_name = "my_session",
            }, "session_deadbeef")
            ngx.say("cookie_name=", opts.cookie_name)
        }
    }
--- response_body
cookie_name=my_session
