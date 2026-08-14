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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # every block here drives resty.openidc into an error path on purpose,
    # which logs at [error]; assert on the specific message instead
    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "no such assertion");
    }
});

run_tests();

__DATA__

=== TEST 1: create a route protected by openid-connect
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/oidc12',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/oidc12/*",
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "redirect_uri": "http://127.0.0.1:1984/oidc12/callback",
                                "ssl_verify": false,
                                "session": {
                                    "secret": "6S8IO+A+6KJsdazbjNyG7g=="
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
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



=== TEST 2: a callback reporting a temporarily unavailable IDP restarts the flow
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function cookie_of(res)
                local c = res.headers["Set-Cookie"]
                if type(c) == "table" then
                    c = table.concat(c, "; ")
                end
                return c and c:match("^([^;]+)")
            end

            -- start a login flow and keep the session cookie
            local res_a = http.new():request_uri(base .. "/oidc12/page")
            local state = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            -- the ID provider redirects back with an error instead of a code,
            -- e.g. the user's login session expired at the IDP
            local res_b = http.new():request_uri(
                base .. "/oidc12/callback?error=temporarily_unavailable" ..
                    "&error_description=authentication_expired&state=" .. state, {
                    headers = {Cookie = jar}
                })
            ngx.say(res_b.status, " ", tostring(res_b.headers["Location"]))
        }
    }
--- response_body
302 /oidc12/page
--- error_log
restarting the authentication flow



=== TEST 3: a callback with a different IDP error still fails with 500
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function cookie_of(res)
                local c = res.headers["Set-Cookie"]
                if type(c) == "table" then
                    c = table.concat(c, "; ")
                end
                return c and c:match("^([^;]+)")
            end

            local res_a = http.new():request_uri(base .. "/oidc12/page")
            local state = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            -- access_denied reflects a deliberate outcome, not a transient
            -- failure, so it must not be silently retried
            local res_b = http.new():request_uri(
                base .. "/oidc12/callback?error=access_denied" ..
                    "&error_description=user+denied+access&state=" .. state, {
                    headers = {Cookie = jar}
                })
            ngx.say(res_b.status)
        }
    }
--- response_body
500



=== TEST 4: a non-GET callback reporting a temporarily unavailable IDP still fails with 500
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function cookie_of(res)
                local c = res.headers["Set-Cookie"]
                if type(c) == "table" then
                    c = table.concat(c, "; ")
                end
                return c and c:match("^([^;]+)")
            end

            local res_a = http.new():request_uri(base .. "/oidc12/page")
            local state = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            local res_b = http.new():request_uri(
                base .. "/oidc12/callback?error=temporarily_unavailable" ..
                    "&error_description=authentication_expired&state=" .. state, {
                    method = "POST",
                    body = "",
                    headers = {Cookie = jar}
                })
            ngx.say(res_b.status)
        }
    }
--- response_body
500



=== TEST 5: a callback reporting a temporarily unavailable IDP without a session cookie still fails with 500
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local res = http.new():request_uri(
                base .. "/oidc12/callback?error=temporarily_unavailable" ..
                    "&error_description=authentication_expired&state=deadbeef")
            ngx.say(res.status)
        }
    }
--- response_body
500



=== TEST 6: a callback error that keeps recurring stops being retried after 3 restarts
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function cookie_of(res)
                local c = res.headers["Set-Cookie"]
                if type(c) == "table" then
                    c = table.concat(c, "; ")
                end
                return c and c:match("^([^;]+)")
            end

            local res_a = http.new():request_uri(base .. "/oidc12/page")
            local state = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            -- the browser keeps following the restart redirect into the same
            -- failure; each response carries the session cookie updated with
            -- the restart count
            local statuses = {}
            for i = 1, 5 do
                local res = http.new():request_uri(
                    base .. "/oidc12/callback?error=temporarily_unavailable" ..
                        "&error_description=authentication_expired&state=" .. state, {
                        headers = {Cookie = jar}
                    })
                statuses[i] = res.status
                jar = cookie_of(res) or jar
            end
            ngx.say(table.concat(statuses, " "))
        }
    }
--- response_body
302 302 302 500 500



=== TEST 7: a successful authentication resets the restart budget
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function cookie_of(res)
                local c = res.headers["Set-Cookie"]
                if type(c) == "table" then
                    c = table.concat(c, "; ")
                end
                return c and c:match("^([^;]+)")
            end

            -- exhaust the restart budget on failing callbacks
            local res_a = http.new():request_uri(base .. "/oidc12/page")
            local state = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            local statuses = {}
            for i = 1, 4 do
                local res = http.new():request_uri(
                    base .. "/oidc12/callback?error=temporarily_unavailable" ..
                        "&error_description=authentication_expired&state=" .. state, {
                        headers = {Cookie = jar}
                    })
                statuses[i] = res.status
                jar = cookie_of(res) or jar
            end

            -- complete a login in the same browser session: fresh flow,
            -- Keycloak login form, then the code callback
            local res_b = http.new():request_uri(base .. "/oidc12/page", {
                headers = {Cookie = jar}
            })
            jar = cookie_of(res_b) or jar

            local httpc = http.new()
            local res_c = httpc:request_uri(res_b.headers["Location"])
            local action, params = res_c.body:match('.*action="(.*)%?(.*)" method="post">')
            params = params:gsub("&amp;", "&")
            local kc_cookies = concatenate_cookies(res_c.headers["Set-Cookie"])

            local res_d = httpc:request_uri(action .. "?" .. params, {
                method = "POST",
                body = "username=jack&password=jack",
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                    Cookie = kc_cookies
                }
            })

            local res_e = http.new():request_uri(res_d.headers["Location"], {
                headers = {Cookie = jar}
            })
            statuses[5] = res_e.status
            jar = cookie_of(res_e) or jar

            -- the authenticated request resets the budget; it passes the
            -- plugin and reaches the mock upstream, which has no
            -- /oidc12/page route, hence its 404
            local res_f = http.new():request_uri(base .. "/oidc12/page", {
                headers = {Cookie = jar}
            })
            statuses[6] = res_f.status
            jar = cookie_of(res_f) or jar

            -- ... so a later transient callback error is retried again
            local res_g = http.new():request_uri(
                base .. "/oidc12/callback?error=temporarily_unavailable" ..
                    "&error_description=authentication_expired&state=deadbeef", {
                    headers = {Cookie = jar}
                })
            statuses[7] = res_g.status
            ngx.say(table.concat(statuses, " "))
        }
    }
--- response_body
302 302 302 500 302 404 302
