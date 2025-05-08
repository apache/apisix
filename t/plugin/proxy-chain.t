use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

# Repeat each test case 1 time (for consistency)
repeat_each(1);

# Set timeout for tests
plan tests => repeat_each() * (3 * blocks());

# Run tests with APISIX Lua module
my $pwd = cwd();
our $HttpConfig = qq{
    lua_package_path "$pwd/?.lua;;";
    lua_package_cpath "$pwd/?.so;;";
};

# Enable APISIX test helpers
no_long_string();
run_tests();

__DATA__

=== TEST 1: Sanity check - plugin schema validation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local ok, err = plugin.check_schema({
                services = {
                    { uri = "http://127.0.0.1:1980/test", method = "POST" }
                },
                token_header = "Token"
            })
            if not ok then
                ngx.say("failed to check schema: ", err)
            else
                ngx.say("schema check passed")
            end
        }
    }
--- request
GET /t
--- response_body
schema check passed
--- no_error_log
[error]

=== TEST 2: Successful chaining - single service with token
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'
            ctx.var.Token = "my-auth-token"

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:1980/test", method = "POST" }
                },
                token_header = "Token"
            }

            local code, body = plugin.access(conf, ctx)
            if code then
                ngx.status = code
                ngx.say(body.error)
            else
                ngx.say(ctx.var.request_body)
            end
        }
    }
    location /test {
        content_by_lua_block {
            ngx.say('{"user_id": "67890"}')
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
{"order_id":"12345","user_id":"67890"}
--- no_error_log
[error]

=== TEST 3: Multiple services chaining
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'
            ctx.var.Token = "my-auth-token"

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:1980/test1", method = "POST" },
                    { uri = "http://127.0.0.1:1980/test2", method = "POST" }
                },
                token_header = "Token"
            }

            local code, body = plugin.access(conf, ctx)
            if code then
                ngx.status = code
                ngx.say(body.error)
            else
                ngx.say(ctx.var.request_body)
            end
        }
    }
    location /test1 {
        content_by_lua_block {
            ngx.say('{"user_id": "67890"}')
        }
    }
    location /test2 {
        content_by_lua_block {
            ngx.say('{"status": "valid"}')
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
{"order_id":"12345","user_id":"67890","status":"valid"}
--- no_error_log
[error]

=== TEST 4: Error handling - service failure
--- config
    location /t {
        access_by_lua_block {
            local plugin = require("apisix.plugins.proxy-chain")
            local core = require("apisix.core")
            local ctx = { var = { method = "POST" } }
            ctx.var.request_body = '{"order_id": "12345"}'

            local conf = {
                services = {
                    { uri = "http://127.0.0.1:1999/nonexistent", method = "POST" }
                }
            }

            local code, body = plugin.access(conf, ctx)
            ngx.status = code
            ngx.say(body.error)
        }
    }
--- request
POST /t
{"order_id": "12345"}
--- response_body
Failed to call service: http://127.0.0.1:1999/nonexistent
--- error_code: 500
--- error_log
Failed to call service http://127.0.0.1:1999/nonexistent
