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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: get_ip
--- config
    location /t {
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
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 2: get_ip
--- config
    location /t {
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
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 3: get_ip and X-Forwarded-For
--- config
    location /t {
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
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 4: get_remote_client_ip
--- config
    location /t {
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
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
10.0.0.1



=== TEST 5: get_remote_client_ip and X-Forwarded-For
--- config
    location /t {
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
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
10.0.0.1



=== TEST 6: get_host
--- config
    location /t {
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
            local host = core.request.get_host(ngx.ctx.api_ctx)
            ngx.say(host)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
localhost



=== TEST 7: get_scheme
--- config
    location /t {
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
            local scheme = core.request.get_scheme(ngx.ctx.api_ctx)
            ngx.say(scheme)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
http



=== TEST 8: get_port
--- config
    location /t {
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
            local port = core.request.get_port(ngx.ctx.api_ctx)
            ngx.say(port)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1984



=== TEST 9: get_http_version
--- config
    location /t {
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
            local http_version = core.request.get_http_version()
            ngx.say(http_version)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1.1



=== TEST 10: set header
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local h = core.request.header(nil, "Test")
            local ctx = ngx.ctx.api_ctx
            core.request.set_header(ctx, "Test", "t")
            local h2 = core.request.header(ctx, "Test")
            ngx.say(h)
            ngx.say(h2)
        }
    }
--- response_body
nil
t



=== TEST 11: get_post_args
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)

            local args = core.request.get_post_args(ngx.ctx.api_ctx)
            ngx.say(args["c"])
            ngx.say(args["v"])
        }
    }
--- request
POST /t
c=z_z&v=x%20x
--- response_body
z_z
x x



=== TEST 12: get_post_args when the body is stored in temp file
--- config
    location /t {
        client_body_in_file_only clean;
        content_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)

            local args = core.request.get_post_args(ngx.ctx.api_ctx)
            ngx.say(args["c"])
        }
    }
--- request
POST /t
c=z_z&v=x%20x
--- response_body
nil
--- error_log
the post form is too large: request body in temp file not supported



=== TEST 13: get_method
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.request.get_method())
        }
    }
--- request
POST /t
--- response_body
POST



=== TEST 14: add header
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local ctx = ngx.ctx.api_ctx
            local json = require("toolkit.json")
            core.request.add_header(ctx, "test_header", "test")
            local h = core.request.header(ctx, "test_header")
            ngx.say(h)
            core.request.add_header(ctx, "test_header", "t2")
            local h2 = core.request.headers(ctx)["test_header"]
            ngx.say(json.encode(h2))
            core.request.add_header(ctx, "test_header", "t3")
            local h3 = core.request.headers(ctx)["test_header"]
            ngx.say(json.encode(h3))
        }
    }
--- response_body
test
["test","t2"]
["test","t2","t3"]



=== TEST 15: call add_header with deprecated way
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local ctx = ngx.ctx.api_ctx
            core.request.add_header("test_header", "test")
            local h = core.request.header(ctx, "test_header")
            ngx.say(h)
        }
    }
--- response_body
test
--- error_log
DEPRECATED: use add_header(ctx, header_name, header_value) instead
