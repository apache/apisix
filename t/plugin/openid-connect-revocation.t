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

=== TEST 1: typical cookie session with redis revocation config passes schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local conf = {
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "cookie",
                    cookie_name = "oidc_session",
                    absolute_timeout = 3600,
                    redis = {
                        host = "redis.internal",
                        port = 6379,
                        password = "secret",
                        database = 1,
                        prefix = "oidc:session:",
                        mode = "revocation",
                        ssl = true,
                        connect_timeout = 1000,
                    },
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            else
                ngx.say("revocation_fail_mode=", conf.session.revocation_fail_mode)
            end
        }
    }
--- response_body
revocation_fail_mode=open



=== TEST 2: build_session_opts passes typical revocation config through unchanged
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local build = plugin._build_session_opts
            local opts = build({
                secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                storage = "cookie",
                cookie_name = "oidc_session",
                absolute_timeout = 3600,
                redis = {
                    host = "redis.internal",
                    port = 6379,
                    password = "secret",
                    database = 1,
                    prefix = "oidc:session:",
                    mode = "revocation",
                },
            })
            ngx.say("cookie_name=", opts.cookie_name)
            ngx.say("absolute_timeout=", opts.absolute_timeout)
            ngx.say("redis.prefix=", opts.redis.prefix)
            ngx.say("redis.mode=", opts.redis.mode)
        }
    }
--- response_body
cookie_name=oidc_session
absolute_timeout=3600
redis.prefix=oidc:session:
redis.mode=revocation



=== TEST 3: typical redis-backed session storage config passes schema
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
                    cookie_name = "oidc_session",
                    redis = {
                        host = "127.0.0.1",
                        port = 6379,
                        password = "secret",
                        prefix = "sessions",
                        mode = "storage",
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



=== TEST 4: build_session_opts passes redis mode through for session storage
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



=== TEST 5: cookie session without redis block is valid
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



=== TEST 6: valid schema with revocation_fail_mode closed
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



=== TEST 7: build_session_opts passes revocation_fail_mode closed
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



=== TEST 8: cookie storage with redis block omitting mode is valid
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



=== TEST 9: redis storage with redis block omitting mode is valid
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



=== TEST 10: build_session_opts passes redis block through when mode is omitted
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
                },
                revocation_fail_mode = "closed",
            })
            ngx.say("storage=", tostring(opts.storage))
            ngx.say("redis.host=", opts.redis.host)
            ngx.say("redis.mode=", tostring(opts.redis.mode))
            ngx.say("revocation_fail_mode=", opts.revocation_fail_mode)
        }
    }
--- response_body
storage=cookie
redis.host=127.0.0.1
redis.mode=nil
revocation_fail_mode=closed



=== TEST 11: cookie storage with redis mode storage is valid
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
                        mode = "storage",
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



=== TEST 12: revocation_fail_mode without redis block on cookie storage is valid
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



=== TEST 13: redis storage with redis mode revocation is valid schema
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
                        mode = "revocation",
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



=== TEST 14: invalid revocation_fail_mode value is rejected
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



=== TEST 15: invalid redis.mode value is rejected
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
                        mode = "bogus",
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
.*redis\.mode.*



=== TEST 16: session.revocation is rejected (use session.redis instead)
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
