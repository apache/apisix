use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: get_ip
--- config
    location = /hello {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1
--- no_error_log
[error]



=== TEST 2: get_ip
--- config
    location = /hello {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1
--- no_error_log
[error]



=== TEST 3: get_ip and X-Forwarded-For
--- config
    location = /hello {
        real_ip_header X-Forwarded-For;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- request
GET /hello
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
127.0.0.1
--- no_error_log
[error]



=== TEST 4: get_remote_client_ip
--- config
    location = /hello {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
10.0.0.1
--- no_error_log
[error]



=== TEST 5: get_remote_client_ip and X-Forwarded-For
--- config
    location = /hello {
        real_ip_header X-Forwarded-For;
        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- request
GET /hello
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
10.0.0.1
--- no_error_log
[error]
