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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set up two routes - one with session.secret_fallbacks, one without
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Route guarded by openid-connect whose CURRENT session.secret is the
            -- "new" key, and whose PREVIOUS key is kept in session.secret_fallbacks.
            -- This models the "flip" stage of a rotation: new cookies are sealed
            -- with `secret`, old cookies still open via a fallback.
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "http://127.0.0.1:1984/callback",
                                "ssl_verify": false,
                                "use_pkce": false,
                                "set_userinfo_header": true,
                                "renew_access_token_on_expiry": false,
                                "unauth_action": "deny",
                                "session": {
                                    "secret": "new_session_secret_at_least_16",
                                    "secret_fallbacks": ["old_session_secret_at_least_16"]
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/uri"
                }]]
                )
            if code >= 300 then
                ngx.say("route 1 failed: ", code)
                return
            end

            -- Same, but WITHOUT secret_fallbacks: a cookie sealed with the old key
            -- can no longer be decrypted. This is the negative control.
            local code = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                "redirect_uri": "http://127.0.0.1:1984/callback",
                                "ssl_verify": false,
                                "use_pkce": false,
                                "set_userinfo_header": true,
                                "renew_access_token_on_expiry": false,
                                "unauth_action": "deny",
                                "session": {
                                    "secret": "new_session_secret_at_least_16"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/uri-no-fallback"
                }]]
                )
            if code >= 300 then
                ngx.say("route 2 failed: ", code)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: a cookie sealed with the OLD key is accepted via secret_fallbacks
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local session = require("resty.session")
            local core = require("apisix.core")

            -- Forge the session openid-connect writes after a successful login,
            -- sealed with the OLD key. With a non-expired access token and
            -- renew_access_token_on_expiry disabled, no IdP is contacted; the
            -- plugin takes the "already authenticated" path and must open the
            -- cookie via session.secret_fallbacks.
            local s = session.new({ secret = "old_session_secret_at_least_16" })
            s:set("authenticated", true)
            s:set("last_authenticated", ngx.time())
            s:set("id_token", { sub = "a UID" })
            s:set("access_token", "fake-access-token")
            s:set("access_token_expiration", ngx.time() + 3600)
            s:set("user", core.json.decode(
                '{"sub":"a UID","name":"Testuser One","roles":[]}'))

            local ok, err = s:save()
            if not ok then
                ngx.say("failed to save session: ", err)
                return
            end

            local cookie = ngx.header["Set-Cookie"]
            if type(cookie) == "table" then
                cookie = cookie[1]
            end
            ngx.header["Set-Cookie"] = nil

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/uri", {
                headers = { Cookie = cookie },
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end

            local has_userinfo = res.body:match("x%-userinfo: ") ~= nil
            if res.status == 200 and has_userinfo then
                ngx.say("fallback-accepted")
            else
                ngx.say("unexpected: status=", res.status,
                        " userinfo=", tostring(has_userinfo))
            end
        }
    }
--- response_body
fallback-accepted



=== TEST 3: negative control - without secret_fallbacks the OLD cookie is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local session = require("resty.session")
            local core = require("apisix.core")

            -- Same OLD-key cookie, but the route has no secret_fallbacks, so the
            -- plugin cannot decrypt it and (unauth_action = deny) returns 401.
            -- This proves the fallback is what makes TEST 2 succeed.
            local s = session.new({ secret = "old_session_secret_at_least_16" })
            s:set("authenticated", true)
            s:set("last_authenticated", ngx.time())
            s:set("id_token", { sub = "a UID" })
            s:set("access_token", "fake-access-token")
            s:set("access_token_expiration", ngx.time() + 3600)
            s:set("user", core.json.decode(
                '{"sub":"a UID","name":"Testuser One","roles":[]}'))

            local ok, err = s:save()
            if not ok then
                ngx.say("failed to save session: ", err)
                return
            end

            local cookie = ngx.header["Set-Cookie"]
            if type(cookie) == "table" then
                cookie = cookie[1]
            end
            ngx.header["Set-Cookie"] = nil

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/uri-no-fallback", {
                headers = { Cookie = cookie },
            })
            if not res then
                ngx.say("request failed: ", err)
                return
            end

            if res.status == 401 then
                ngx.say("no-fallback-rejected")
            else
                ngx.say("unexpected: status=", res.status)
            end
        }
    }
--- response_body
no-fallback-rejected
