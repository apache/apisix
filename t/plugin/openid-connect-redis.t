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

=== TEST 1: check schema with valid redis session configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        host = "127.0.0.1",
                        port = 6379,
                        prefix = "mysessions",
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: check schema with invalid redis session configuration (port string)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        port = "invalid",
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body_like
property "port" validation failed: wrong type: expected integer, got string



=== TEST 3: verify session sharing across routes with Redis (Simulate Refresh Scenario)
--- http_config
    server {
        listen 11980;
        server_name localhost;

        location / {
            content_by_lua_block {
                ngx.say("lesgooo!!")
            }
        }
    }
    server {
        listen 16969;
        server_name localhost;

        location /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[
                {
                    "issuer": "http://127.0.0.1:16969",
                    "authorization_endpoint": "http://127.0.0.1:16969/authorize",
                    "token_endpoint": "http://127.0.0.1:16969/token",
                    "userinfo_endpoint": "http://127.0.0.1:16969/userinfo",
                    "jwks_uri": "http://127.0.0.1:16969/jwks"
                }
                ]])
            }
        }

        location /token {
            content_by_lua_block {
                local jwt = require("resty.jwt")
                local validators = require("resty.jwt-validators")
                local cjson = require("cjson")

                ngx.header.content_type = "application/json"
                ngx.req.read_body()
                local args = ngx.req.get_post_args()

                if args.grant_type == "authorization_code" then
                    local claim_spec = {
                       sub = "user_123",
                       iss = "http://127.0.0.1:16969",
                       aud = "test_client",
                       exp = ngx.time() + 60,
                       iat = ngx.time(),
                       name = "Test User"
                    }

                    local jwt_token = jwt:sign(
                       "test_secret",
                       {
                           header = {typ = "JWT", alg = "HS256"},
                           payload = claim_spec
                       }
                    )

                    ngx.say(cjson.encode({
                       access_token = "access_token_1",
                       expires_in = 1,
                       refresh_token = "refresh_token_1",
                       id_token = jwt_token,
                       token_type = "Bearer"
                    }))
                elseif args.grant_type == "refresh_token" then
                    -- Verify that the refresh token matches what we issued
                    if args.refresh_token == "refresh_token_1" then
                        local claim_spec = {
                           sub = "user_123",
                           iss = "http://127.0.0.1:16969",
                           aud = "test_client",
                           exp = ngx.time() + 3600,
                           iat = ngx.time(),
                           name = "Test User"
                        }

                        local jwt_token = jwt:sign(
                           "test_secret",
                           {
                               header = {typ = "JWT", alg = "HS256"},
                               payload = claim_spec
                           }
                        )

                        ngx.say(cjson.encode({
                           access_token = "access_token_2",
                           expires_in = 3600,
                           refresh_token = "refresh_token_2",
                           id_token = jwt_token,
                           token_type = "Bearer"
                        }))
                    else
                        ngx.status = 400
                        ngx.say('{"error":"invalid_grant"}')
                    end
                else
                    ngx.status = 400
                    ngx.say('{"error":"unsupported_grant_type"}')
                end
            }
        }

        location /userinfo {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{"sub": "user_123", "name": "Test User"}]])
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

            -- Create Route 1
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "test_client",
                            "client_secret": "test_secret",
                            "discovery": "http://127.0.0.1:16969/.well-known/openid-configuration",
                            "redirect_uri": "http://127.0.0.1/api/route1/callback",
                            "session": {
                                "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                "storage": "redis",
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "prefix": "test_shared_sessions"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api/route1*"
                }]=]
            )

            if code >= 300 then
                ngx.say("setup route 1 failed")
                return
            end

            -- Create Route 2
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "openid-connect": {
                            "client_id": "test_client",
                            "client_secret": "test_secret",
                            "discovery": "http://127.0.0.1:16969/.well-known/openid-configuration",
                            "redirect_uri": "http://127.0.0.1/api/route2/callback",
                            "session": {
                                "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                "storage": "redis",
                                "redis": {
                                    "host": "127.0.0.1",
                                    "port": 6379,
                                    "prefix": "test_shared_sessions"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api/route2*"
                }]=]
            )

            if code >= 300 then
                ngx.say("setup route 2 failed")
                return
            end

            local httpc = http.new()

            -- extract cookie value by name from Set-Cookie heade
            local function get_cookie(headers, name)
                local cookies = headers["Set-Cookie"]
                if not cookies then return nil end
                if type(cookies) == "string" then cookies = { cookies } end
                for _, c in ipairs(cookies) do
                    local val = string.match(c, name .. "=([^;]+)")
                    if val then return name .. "=" .. val end
                end
                return nil
            end

            -- access without login state
            local uri_start = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/route1/start"
            local res, err = httpc:request_uri(uri_start, { method = "GET" })

            if not res or res.status ~= 302 then
                ngx.say("failed to start flow: ", res and res.status or err)
                return
            end

            local initial_cookie = get_cookie(res.headers, "session")
            if not initial_cookie then
                ngx.say("failed to get initial session cookie")
                return
            end

            -- extract state from the Location URL egample: http://.../authorize?client_id=...&state=...&nonce=...
            local loc = res.headers["Location"]
            local state = string.match(loc, "state=([^&]+)")
            if not state then
                ngx.say("failed to extract state from location header")
                return
            end

            -- act as the IdP redirecting back with the code and the SAME state.
            local uri_cb = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/route1/callback?code=mock_code&state=" .. state
            res, err = httpc:request_uri(uri_cb, {
                method = "GET",
                headers = {
                    ["Cookie"] = initial_cookie
                }
            })

            -- We expect a successful login (likely redirect to original URL or 200)
            if not res then
                ngx.say("callback request failed: ", err)
                return
            end

            -- After callback, we get the FINAL authenticated session cookie.
            local auth_cookie = get_cookie(res.headers, "session")
            if not auth_cookie then
                ngx.say("failed to get authenticated session cookie after callback. status: ", res.status)
                return
            end
            ngx.log(ngx.INFO, "dibag auth_cookie: ", auth_cookie)

            -- wait for token expiry as our mock idp issues tokens with 'expires_in: 1'
            ngx.sleep(2)

            -- access route 2 with the expired (but valid refresh) session
            local uri_r2 = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/route2/resource"
            local res, err = httpc:request_uri(uri_r2, {
                method = "GET",
                headers = {
                    ["Cookie"] = auth_cookie
                }
            })

            if not res then
                ngx.say("request to route 2 failed: ", err)
                return
            end

            if res.status == 200 then
                ngx.say("refresh successful - request passed to upstream")
            elseif res.status == 302 then
                ngx.say("refresh failed - redirected to login")
            else
                ngx.say("unexpected status: ", res.status, " body: ", res.body)
            end

        }
    }
--- request
GET /t
--- response_body
refresh successful - request passed to upstream
--- no_error_log
[error]



=== TEST 4: check schema with missing redis configuration when storage is redis
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    -- redis object missing
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "session" validation failed: then clause did not match
