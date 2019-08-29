use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("remote_addr: ", ctx.var["remote_addr"])
            ngx.say("server_port: ", ctx.var["server_port"])
        }
    }
--- request
GET /t
--- response_body
remote_addr: 127.0.0.1
server_port: 1984
--- no_error_log
[error]



=== TEST 2: http header + arg
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("http_host: ", ctx.var["http_host"])
            ngx.say("arg_a: ", ctx.var["arg_a"])
        }
    }
--- request
GET /t?a=aaa
--- response_body
http_host: localhost
arg_a: aaa
--- no_error_log
[error]



=== TEST 3: cookie + no cookie
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_host: ", ctx.var["cookie_host"])
        }
    }
--- request
GET /t?a=aaa
--- response_body
cookie_host: nil
--- error_log
failed to fetch cookie value by name: cookie_host error: no cookie found in the current request



=== TEST 4: cookie
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_a: ", ctx.var["cookie_a"])
            ngx.say("cookie_b: ", ctx.var["cookie_b"])
            ngx.say("cookie_c: ", ctx.var["cookie_c"])
            ngx.say("cookie_d: ", ctx.var["cookie_d"])
        }
    }
--- more_headers
Cookie: a=a; b=bb; c=ccc
--- request
GET /t?a=aaa
--- response_body
cookie_a: a
cookie_b: bb
cookie_c: ccc
cookie_d: nil
--- no_error_log
[error]
