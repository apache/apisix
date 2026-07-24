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
            local code, body = t('/apisix/admin/routes/oidc11',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/oidc11/*",
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "redirect_uri": "http://127.0.0.1:1984/oidc11/callback",
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



=== TEST 2: a callback whose state was overwritten by a second tab redirects back
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

            -- first tab: start a login flow and keep the session cookie
            local res_a = http.new():request_uri(base .. "/oidc11/page?tab=A")
            local state_a = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            -- second tab in the same browser: overwrites the state in the session
            local res_b = http.new():request_uri(base .. "/oidc11/page?tab=B", {
                headers = {Cookie = jar}
            })
            jar = cookie_of(res_b)

            -- the first tab's callback now carries a stale state
            local res_c = http.new():request_uri(
                base .. "/oidc11/callback?code=dummy&state=" .. state_a, {
                    headers = {Cookie = jar}
                })
            ngx.say(res_c.status, " ", tostring(res_c.headers["Location"]))
        }
    }
--- response_body
302 /oidc11/page?tab=B
--- error_log
does not match state restored from session



=== TEST 3: a non-GET callback with a stale state still fails with 500
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

            local res_a = http.new():request_uri(base .. "/oidc11/page?tab=A")
            local state_a = res_a.headers["Location"]:match("state=([^&]+)")
            local jar = cookie_of(res_a)

            local res_b = http.new():request_uri(base .. "/oidc11/page?tab=B", {
                headers = {Cookie = jar}
            })
            jar = cookie_of(res_b)

            local res_c = http.new():request_uri(
                base .. "/oidc11/callback?code=dummy&state=" .. state_a, {
                    method = "POST",
                    body = "",
                    headers = {Cookie = jar}
                })
            ngx.say(res_c.status)
        }
    }
--- response_body
500



=== TEST 4: a callback without a session cookie still fails with 500
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local res = http.new():request_uri(
                base .. "/oidc11/callback?code=dummy&state=deadbeef")
            ngx.say(res.status)
        }
    }
--- response_body
500
