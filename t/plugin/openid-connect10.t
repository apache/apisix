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

=== TEST 1: valid session with cookie settings (lua-resty-session 4.x)
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
                    cookie_domain = "example.com",
                    cookie_http_only = true,
                    cookie_secure = true,
                    cookie_same_site = "Strict",
                    cookie_priority = "High",
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



=== TEST 2: valid session with timeout settings
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
                    idling_timeout = 600,
                    rolling_timeout = 1800,
                    absolute_timeout = 43200,
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



=== TEST 3: valid session with remember settings
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
                    remember = true,
                    remember_cookie_name = "persist",
                    remember_rolling_timeout = 604800,
                    remember_absolute_timeout = 2592000,
                    remember_safety = "High",
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



=== TEST 4: valid session with miscellaneous settings
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
                    audience = "my-app",
                    subject = "user123",
                    enforce_same_subject = true,
                    stale_ttl = 30,
                    touch_threshold = 120,
                    compression_threshold = 2048,
                    hash_storage_key = true,
                    hash_subject = true,
                    store_metadata = true,
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



=== TEST 5: valid session with all resty.session 4.x options combined
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
                    cookie_path = "/",
                    cookie_http_only = true,
                    cookie_secure = true,
                    cookie_same_site = "Lax",
                    idling_timeout = 900,
                    rolling_timeout = 3600,
                    absolute_timeout = 86400,
                    remember = false,
                    audience = "default",
                    stale_ttl = 10,
                    touch_threshold = 60,
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



=== TEST 6: invalid cookie_same_site value
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
                    cookie_same_site = "Invalid",
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
property "session" validation failed: property "cookie_same_site" validation failed.*



=== TEST 7: invalid cookie_priority value
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
                    cookie_priority = "SuperHigh",
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
property "session" validation failed: property "cookie_priority" validation failed.*



=== TEST 8: invalid remember_safety value
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
                    remember_safety = "Invalid",
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
property "session" validation failed: property "remember_safety" validation failed.*



=== TEST 9: invalid type for idling_timeout (string instead of integer)
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
                    idling_timeout = "invalid",
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
property "idling_timeout" validation failed: wrong type: expected integer, got string



=== TEST 10: invalid type for cookie_http_only (string instead of boolean)
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
                    cookie_http_only = "yes",
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
property "cookie_http_only" validation failed: wrong type: expected boolean, got string



=== TEST 11: deprecated cookie.lifetime is rejected (additionalProperties = false)
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
                        lifetime = 3600
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
property "session" validation failed: additional properties forbidden, found cookie



=== TEST 12: valid session with cookie_partitioned and cookie_same_party
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
                    cookie_partitioned = true,
                    cookie_same_party = true,
                    cookie_prefix = "__Secure-",
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



=== TEST 13: valid session with redis and new session options combined
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
                    cookie_same_site = "None",
                    cookie_secure = true,
                    idling_timeout = 300,
                    rolling_timeout = 1800,
                    absolute_timeout = 7200,
                    remember = true,
                    remember_rolling_timeout = 86400,
                    remember_absolute_timeout = 604800,
                    remember_safety = "Very High",
                    audience = "my-api",
                    hash_storage_key = true,
                    store_metadata = true,
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



=== TEST 14: unknown session property is rejected
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
                    unknown_property = "value",
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
property "session" validation failed: additional properties forbidden, found unknown_property
