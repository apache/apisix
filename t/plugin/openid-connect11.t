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

run_tests();

__DATA__

=== TEST 1: sibling routes sharing session.secret get isolated session cookies
--- http_config
    server {
        listen 16970;
        server_name localhost;

        location /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[
                {
                    "issuer": "http://127.0.0.1:16970",
                    "authorization_endpoint": "http://127.0.0.1:16970/authorize",
                    "token_endpoint": "http://127.0.0.1:16970/token",
                    "userinfo_endpoint": "http://127.0.0.1:16970/userinfo",
                    "jwks_uri": "http://127.0.0.1:16970/jwks"
                }
                ]])
            }
        }

        location /jwks {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{"keys": []}]])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local host = "oidc-isolation.test"

            local function route(uri, redirect)
                return [=[{
                    "host": "]=] .. host .. [=[",
                    "plugins": {
                        "openid-connect": {
                            "client_id": "test_client",
                            "client_secret": "test_secret",
                            "discovery": "http://127.0.0.1:16970/.well-known/openid-configuration",
                            "redirect_uri": "]=] .. redirect .. [=[",
                            "ssl_verify": false,
                            "session": {
                                "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": { "127.0.0.1:1980": 1 },
                        "type": "roundrobin"
                    },
                    "uri": "]=] .. uri .. [=["
                }]=]
            end

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                           route("/api/low/*", "http://127.0.0.1/api/low/callback"))
            if code >= 300 then ngx.say("setup low failed: " .. code); return end
            local code = t('/apisix/admin/routes/2', ngx.HTTP_PUT,
                           route("/api/high/*", "http://127.0.0.1/api/high/callback"))
            if code >= 300 then ngx.say("setup high failed: " .. code); return end
            ngx.sleep(0.5)

            local function cookie_name(headers)
                local cookies = headers["Set-Cookie"]
                if type(cookies) == "string" then cookies = { cookies } end
                for _, c in ipairs(cookies or {}) do
                    local name = c:match("^([^=]+)=")
                    if name and name:find("^session") then
                        return name
                    end
                end
                return nil
            end

            local httpc = http.new()
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local res_a = httpc:request_uri(base .. "/api/low/data",
                                             {method = "GET", headers = {Host = host}})
            local res_b = httpc:request_uri(base .. "/api/high/data",
                                             {method = "GET", headers = {Host = host}})

            local name_a = cookie_name(res_a.headers)
            local name_b = cookie_name(res_b.headers)
            ngx.say("status_a=", res_a.status)
            ngx.say("status_b=", res_b.status)
            ngx.say("has_names=", tostring(name_a ~= nil and name_b ~= nil))
            ngx.say("names_differ=", tostring(name_a ~= name_b))
        }
    }
--- request
GET /t
--- response_body
status_a=302
status_b=302
has_names=true
names_differ=true
--- no_error_log
[error]
