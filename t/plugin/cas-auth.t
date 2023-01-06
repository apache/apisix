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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: Add route for sp1
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_cas")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host" : "127.0.0.1",
                        "plugins": {
                            "cas-auth": ]] .. core.json.encode(opts) .. [[
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: login and logout ok
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_cas"

            local path = "/uri"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, cas_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie
                }
            })
            assert(res.status == 200)
            ngx.say(res.body)

            res, err = kc.logout_keycloak(uri .. "/logout", cas_cookie, keycloak_cookie)
            assert(res.status == 200)
        }
    }
--- response_body_like
uri: /uri
cookie: .*
host: 127.0.0.1:1984
user-agent: .*
x-real-ip: 127.0.0.1



=== TEST 3: Add route for sp2
--- config
    location /t {
        content_by_lua_block {
            local kc = require("lib.keycloak_cas")
            local core = require("apisix.core")

            local default_opts = kc.get_default_opts()
            local opts = core.table.deepcopy(default_opts)
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/cas2',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST"],
                        "host" : "127.0.0.2",
                        "plugins": {
                            "cas-auth": ]] .. core.json.encode(opts) .. [[
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: login sp1 and sp2, then do single logout
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local kc = require "lib.keycloak_cas"

            local path = "/uri"

            -- login to sp1
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            local username = "test"
            local password = "test"

            local res, err, cas_cookie, keycloak_cookie = kc.login_keycloak(uri .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie
                }
            })
            assert(res.status == 200)

            -- login to sp2, which would skip login at keycloak side
            local uri2 = "http://127.0.0.2:" .. ngx.var.server_port

            local res, err, cas_cookie2 = kc.login_keycloak_for_second_sp(uri2 .. path, keycloak_cookie)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri2 .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie2
                }
            })
            assert(res.status == 200)

            -- SLO (single logout)
            res, err = kc.logout_keycloak(uri .. "/logout", cas_cookie, keycloak_cookie)
            assert(res.status == 200)

            -- login to sp2, which would do normal login process at keycloak side
            local res, err, cas_cookie2, keycloak_cookie = kc.login_keycloak(uri2 .. path, username, password)
            if err or res.headers['Location'] ~= path then
                ngx.log(ngx.ERR, err)
                ngx.exit(500)
            end
            res, err = httpc:request_uri(uri .. res.headers['Location'], {
                method = "GET",
                headers = {
                    ["Cookie"] = cas_cookie2
                }
            })
            assert(res.status == 200)

            -- logout sp2
            res, err = kc.logout_keycloak(uri2 .. "/logout", cas_cookie2, keycloak_cookie)
            assert(res.status == 200)
        }
    }
