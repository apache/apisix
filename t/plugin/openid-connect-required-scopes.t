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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set up a route protected by a session, requiring a scope the ID provider grants
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/*",
                "plugins": {
                    "openid-connect": {
                        "client_id": "apisix",
                        "client_secret": "secret",
                        "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                        "redirect_uri": "http://127.0.0.1:1984/authenticated",
                        "ssl_verify": false,
                        "session": { "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                        "required_scopes": ["profile"]
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:1980": 1 }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: log in and reach the upstream, the session carries the required scope
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "jack", "jack")
            if not res then
                ngx.say(err)
                return
            end

            local location = res.headers['Location']
            if location:sub(1, 1) == "/" then
                location = "http://127.0.0.1:" .. ngx.var.server_port .. location
            end

            local httpc = http.new()
            res, err = httpc:request_uri(location, {
                method = "GET",
                headers = { ["Cookie"] = concatenate_cookies(res.headers['Set-Cookie']) },
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- response_body
200



=== TEST 3: require a scope the ID provider does not grant
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/*",
                "plugins": {
                    "openid-connect": {
                        "client_id": "apisix",
                        "client_secret": "secret",
                        "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                        "redirect_uri": "http://127.0.0.1:1984/authenticated",
                        "ssl_verify": false,
                        "session": { "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                        "required_scopes": ["super-admin"]
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:1980": 1 }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: a session missing the required scope is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "jack", "jack")
            if not res then
                ngx.say(err)
                return
            end

            local location = res.headers['Location']
            if location:sub(1, 1) == "/" then
                location = "http://127.0.0.1:" .. ngx.var.server_port .. location
            end

            local httpc = http.new()
            res, err = httpc:request_uri(location, {
                method = "GET",
                headers = { ["Cookie"] = concatenate_cookies(res.headers['Set-Cookie']) },
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
            ngx.say(res.body)
        }
    }
--- response_body
403
{"error":"required scopes super-admin not present"}
--- error_log
required scopes not present



=== TEST 5: restricting session_contents does not drop the scope check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/*",
                "plugins": {
                    "openid-connect": {
                        "client_id": "apisix",
                        "client_secret": "secret",
                        "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                        "redirect_uri": "http://127.0.0.1:1984/authenticated",
                        "ssl_verify": false,
                        "session": { "secret": "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK" },
                        "session_contents": { "id_token": true },
                        "required_scopes": ["profile"]
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:1980": 1 }
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: the granted scope is still read from the session
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local login_keycloak = require("lib.keycloak").login_keycloak
            local concatenate_cookies = require("lib.keycloak").concatenate_cookies

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = login_keycloak(uri, "jack", "jack")
            if not res then
                ngx.say(err)
                return
            end

            local location = res.headers['Location']
            if location:sub(1, 1) == "/" then
                location = "http://127.0.0.1:" .. ngx.var.server_port .. location
            end

            local httpc = http.new()
            res, err = httpc:request_uri(location, {
                method = "GET",
                headers = { ["Cookie"] = concatenate_cookies(res.headers['Set-Cookie']) },
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- response_body
200
