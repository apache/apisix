use t::APISIX 'no_plan';

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: Minimal backchannel_logout config passes the schema check.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "/logout/backchannel"
                }
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: backchannel_logout is rejected together with bearer_only.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                bearer_only = true,
                backchannel_logout = {
                    path = "/logout/backchannel"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say(err)
        }
    }
--- response_body
backchannel_logout cannot be used with bearer_only



=== TEST 3: storage redis without a redis config and without session.redis is rejected.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "/logout/backchannel",
                    storage = "redis"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say(err)
        }
    }
--- response_body
backchannel_logout.redis is required when backchannel_logout.storage is redis and session.redis is not configured



=== TEST 4: A path that does not start with a slash is rejected.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "course_management",
                client_secret = "secret",
                discovery = "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                },
                backchannel_logout = {
                    path = "logout"
                }
            })
            if ok then
                ngx.say("unexpectedly passed")
                return
            end
            ngx.say("rejected")
        }
    }
--- response_body
rejected
