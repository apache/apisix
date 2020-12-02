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



=== TEST 6: get_host
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
            local host = core.request.get_host(ngx.ctx.api_ctx)
            ngx.say(host)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
localhost
--- no_error_log
[error]



=== TEST 7: get_scheme
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
            local scheme = core.request.get_scheme(ngx.ctx.api_ctx)
            ngx.say(scheme)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
http
--- no_error_log
[error]



=== TEST 8: get_port
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
            local port = core.request.get_port(ngx.ctx.api_ctx)
            ngx.say(port)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1984
--- no_error_log
[error]



=== TEST 9: get_http_version
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
            local http_version = core.request.get_http_version()
            ngx.say(http_version)
        }
    }
--- request
GET /hello
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1.1
--- no_error_log
[error]



=== TEST 10: set header
--- config
    location = /hello {
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
--- request
GET /hello
--- response_body
nil
t
--- no_error_log
[error]
