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

=== TEST 1: set up a route guarded by openid-connect with set_userinfo_header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
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
                                "session": {
                                    "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK"
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
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: an empty userinfo claim reaches the upstream as an array
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local session = require("resty.session")
            local core = require("apisix.core")

            -- Forge the session openid-connect writes after a successful login,
            -- so the plugin takes the "already authenticated" path and restores
            -- the userinfo from the session, exactly as it does on every request
            -- after the callback. No IdP is contacted: with a non-expired access
            -- token and renew_access_token_on_expiry disabled, openidc never
            -- reaches for the discovery document.
            local s = session.new({ secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" })
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

            -- the upstream echoes back the request headers it received
            local encoded = res.body:match("x%-userinfo: ([%w+/=]+)")
            if not encoded then
                ngx.say("no X-Userinfo reached the upstream")
                return
            end

            local userinfo = ngx.decode_base64(encoded)
            ngx.say(core.json.encode(core.json.decode(userinfo).roles))
        }
    }
--- response_body
[]
