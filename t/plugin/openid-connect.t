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
run_tests;

__DATA__

=== TEST 1: Sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = "a", client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: Missing `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" is required
done
--- no_error_log
[error]



=== TEST 3: Wrong type for `client_id`.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = 123, client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 4: Set up new route with plugin matching URI `/hello`.
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
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "http://127.0.0.1:1980/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: Access route w/o bearer token. Should redirect to authentication endpoint of ID provider.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if location and string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=https://iresty.com') ~= -1 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- timeout: 10s
--- response_body
true
--- error_code: 302
--- no_error_log
[error]



=== TEST 6: Modify route to match catch-all URI `/*` and point plugin to local Keycloak instance.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": false,
                                "set_id_token_header": true,
                                "set_userinfo_header": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                    "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "realm": "University",
                                    "introspection_endpoint_auth_method": "client_secret_post",
                                    "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                    "set_access_token_header": true,
                                    "access_token_in_authorization_header": false,
                                    "set_id_token_header": true,
                                    "set_userinfo_header": true
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/*"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: Access route w/o bearer token and go through the full OIDC Relying Party authentication process.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Invoke /uri endpoint w/o bearer token. Should receive redirect to Keycloak authorization endpoint.
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = httpc:request_uri(uri, {method = "GET"})

            if not res then
                -- No response, must be an error.
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 302 then
                -- Not a redirect which we expect.
                -- Use 500 to indicate error.
                ngx.status = 500
                ngx.say("Initial request was not redirected to ID provider authorization endpoint.")
                return
            else
                -- Redirect to ID provider's authorization endpoint.

                -- Extract nonce and state from response header.
                local nonce = res.headers['Location']:match('.*nonce=([^&]+).*')
                local state = res.headers['Location']:match('.*state=([^&]+).*')

                -- Extract cookies. Important since OIDC module tracks state with a session cookie.
                local cookies = res.headers['Set-Cookie']

                -- Concatenate cookies into one string as expected when sent in request header.
                local cookie_str = ""

                if type(cookies) == 'string' then
                    cookie_str = cookies:match('([^;]*); .*')
                else
                    -- Must be a table.
                    local len = #cookies
                    if len > 0 then
                        cookie_str = cookies[1]:match('([^;]*); .*')
                        for i = 2, len do
                            cookie_str = cookie_str .. "; " .. cookies[i]:match('([^;]*); .*')
                        end
                    end
                end

                -- Call authorization endpoint we were redirected to.
                -- Note: This typically returns a login form which is the case here for Keycloak as well.
                -- However, how we process the form to perform the login is specific to Keycloak and
                -- possibly even the version used.
                res, err = httpc:request_uri(res.headers['Location'], {method = "GET"})

                if not res then
                    -- No response, must be an error.
                    ngx.status = 500
                    ngx.say(err)
                    return
                elseif res.status ~= 200 then
                    -- Unexpected response.
                    ngx.status = res.status
                    ngx.say(res.body)
                    return
                end

                -- Check if response code was ok.
                if res.status == 200 then
                    -- From the returned form, extract the submit URI and parameters.
                    local uri, params = res.body:match('.*action="(.*)%?(.*)" method="post">')

                    -- Substitute escaped ampersand in parameters.
                    params = params:gsub("&amp;", "&")

                    -- Get all cookies returned. Probably not so important since not part of OIDC specification.
                    local auth_cookies = res.headers['Set-Cookie']

                    -- Concatenate cookies into one string as expected when sent in request header.
                    local auth_cookie_str = ""

                    if type(auth_cookies) == 'string' then
                        auth_cookie_str = auth_cookies:match('([^;]*); .*')
                    else
                        -- Must be a table.
                        local len = #auth_cookies
                        if len > 0 then
                            auth_cookie_str = auth_cookies[1]:match('([^;]*); .*')
                            for i = 2, len do
                                auth_cookie_str = auth_cookie_str .. "; " .. auth_cookies[i]:match('([^;]*); .*')
                            end
                        end
                    end

                    -- Invoke the submit URI with parameters and cookies, adding username and password in the body.
                    -- Note: Username and password are specific to the Keycloak Docker image used.
                    res, err = httpc:request_uri(uri .. "?" .. params, {
                            method = "POST",
                            body = "username=teacher@gmail.com&password=123456",
                            headers = {
                                ["Content-Type"] = "application/x-www-form-urlencoded",
                                ["Cookie"] = auth_cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 302 then
                        -- Not a redirect which we expect.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Login form submission did not return redirect to redirect URI.")
                        return
                    end

                    -- Extract the redirect URI from the response header.
                    -- TODO: Consider validating this against the plugin configuration.
                    local redirect_uri = res.headers['Location']

                    -- Invoke the redirect URI (which contains the authorization code as an URL parameter).
                    res, err = httpc:request_uri(redirect_uri, {
                            method = "GET",
                            headers = {
                                ["Cookie"] = cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 302 then
                        -- Not a redirect which we expect.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Invoking redirect URI with authorization code did not return redirect to original URI.")
                        return
                    end

                    -- Get all cookies returned. This should update the session cookie maintained by the OIDC module with the new state.
                    -- E.g. the session cookie should now contain the access token, ID token and user info.
                    -- The cookie itself should however be treated as opaque.
                    cookies = res.headers['Set-Cookie']

                    -- Concatenate cookies into one string as expected when sent in request header.
                    if type(cookies) == 'string' then
                        cookie_str = cookies:match('([^;]*); .*')
                    else
                        -- Must be a table.
                        local len = #cookies
                        if len > 0 then
                            cookie_str = cookies[1]:match('([^;]*); .*')
                            for i = 2, len do
                                cookie_str = cookie_str .. "; " .. cookies[i]:match('([^;]*); .*')
                            end
                        end
                    end

                    -- Get the final URI out of the Location response header. This should be the original URI that was requested.
                    -- TODO: Consider checking the URI against the original request URI.
                    redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']

                    -- Make the final call back to the original URI.
                    res, err = httpc:request_uri(redirect_uri, {
                            method = "GET",
                            headers = {
                                ["Cookie"] = cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 200 then
                        -- Not a valid response.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Invoking the original URI didn't return the expected result.")
                        return
                    end

                    ngx.status = res.status
                    ngx.say(res.body)
                else
                    -- Response from Keycloak not ok.
                    ngx.say(false)
                end
            end
        }
    }
--- request
GET /t
--- response_body_like
uri: /uri
cookie: .*
host: 127.0.0.1
user-agent: .*
x-access-token: ey.*
x-id-token: ey.*
x-real-ip: 127.0.0.1
x-userinfo: ey.*
--- no_error_log
[error]



=== TEST 8: Re-configure plugin with respect to headers that get sent to upstream.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                "realm": "University",
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                "ssl_verify": false,
                                "timeout": 10,
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": true,
                                "set_id_token_header": false,
                                "set_userinfo_header": false
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                    "redirect_uri": "http://127.0.0.1:]] .. ngx.var.server_port .. [[/authenticated",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "realm": "University",
                                    "introspection_endpoint_auth_method": "client_secret_post",
                                    "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect",
                                    "set_access_token_header": true,
                                    "access_token_in_authorization_header": true,
                                    "set_id_token_header": false,
                                    "set_userinfo_header": false
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/*"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: Access route w/o bearer token and go through the full OIDC Relying Party authentication process.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Invoke /uri endpoint w/o bearer token. Should receive redirect to Keycloak authorization endpoint.
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/uri"
            local res, err = httpc:request_uri(uri, {method = "GET"})

            if not res then
                -- No response, must be an error.
                ngx.status = 500
                ngx.say(err)
                return
            elseif res.status ~= 302 then
                -- Not a redirect which we expect.
                -- Use 500 to indicate error.
                ngx.status = 500
                ngx.say("Initial request was not redirected to ID provider authorization endpoint.")
                return
            else
                -- Redirect to ID provider's authorization endpoint.

                -- Extract nonce and state from response header.
                local nonce = res.headers['Location']:match('.*nonce=([^&]+).*')
                local state = res.headers['Location']:match('.*state=([^&]+).*')

                -- Extract cookies. Important since OIDC module tracks state with a session cookie.
                local cookies = res.headers['Set-Cookie']

                -- Concatenate cookies into one string as expected when sent in request header.
                local cookie_str = ""

                if type(cookies) == 'string' then
                    cookie_str = cookies:match('([^;]*); .*')
                else
                    -- Must be a table.
                    local len = #cookies
                    if len > 0 then
                        cookie_str = cookies[1]:match('([^;]*); .*')
                        for i = 2, len do
                            cookie_str = cookie_str .. "; " .. cookies[i]:match('([^;]*); .*')
                        end
                    end
                end

                -- Call authorization endpoint we were redirected to.
                -- Note: This typically returns a login form which is the case here for Keycloak as well.
                -- However, how we process the form to perform the login is specific to Keycloak and
                -- possibly even the version used.
                res, err = httpc:request_uri(res.headers['Location'], {method = "GET"})

                if not res then
                    -- No response, must be an error.
                    ngx.status = 500
                    ngx.say(err)
                    return
                elseif res.status ~= 200 then
                    -- Unexpected response.
                    ngx.status = res.status
                    ngx.say(res.body)
                    return
                end

                -- Check if response code was ok.
                if res.status == 200 then
                    -- From the returned form, extract the submit URI and parameters.
                    local uri, params = res.body:match('.*action="(.*)%?(.*)" method="post">')

                    -- Substitute escaped ampersand in parameters.
                    params = params:gsub("&amp;", "&")

                    -- Get all cookies returned. Probably not so important since not part of OIDC specification.
                    local auth_cookies = res.headers['Set-Cookie']

                    -- Concatenate cookies into one string as expected when sent in request header.
                    local auth_cookie_str = ""

                    if type(auth_cookies) == 'string' then
                        auth_cookie_str = auth_cookies:match('([^;]*); .*')
                    else
                        -- Must be a table.
                        local len = #auth_cookies
                        if len > 0 then
                            auth_cookie_str = auth_cookies[1]:match('([^;]*); .*')
                            for i = 2, len do
                                auth_cookie_str = auth_cookie_str .. "; " .. auth_cookies[i]:match('([^;]*); .*')
                            end
                        end
                    end

                    -- Invoke the submit URI with parameters and cookies, adding username and password in the body.
                    -- Note: Username and password are specific to the Keycloak Docker image used.
                    res, err = httpc:request_uri(uri .. "?" .. params, {
                            method = "POST",
                            body = "username=teacher@gmail.com&password=123456",
                            headers = {
                                ["Content-Type"] = "application/x-www-form-urlencoded",
                                ["Cookie"] = auth_cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 302 then
                        -- Not a redirect which we expect.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Login form submission did not return redirect to redirect URI.")
                        return
                    end

                    -- Extract the redirect URI from the response header.
                    -- TODO: Consider validating this against the plugin configuration.
                    local redirect_uri = res.headers['Location']

                    -- Invoke the redirect URI (which contains the authorization code as an URL parameter).
                    res, err = httpc:request_uri(redirect_uri, {
                            method = "GET",
                            headers = {
                                ["Cookie"] = cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 302 then
                        -- Not a redirect which we expect.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Invoking redirect URI with authorization code did not return redirect to original URI.")
                        return
                    end

                    -- Get all cookies returned. This should update the session cookie maintained by the OIDC module with the new state.
                    -- E.g. the session cookie should now contain the access token, ID token and user info.
                    -- The cookie itself should however be treated as opaque.
                    cookies = res.headers['Set-Cookie']

                    -- Concatenate cookies into one string as expected when sent in request header.
                    if type(cookies) == 'string' then
                        cookie_str = cookies:match('([^;]*); .*')
                    else
                        -- Must be a table.
                        local len = #cookies
                        if len > 0 then
                            cookie_str = cookies[1]:match('([^;]*); .*')
                            for i = 2, len do
                                cookie_str = cookie_str .. "; " .. cookies[i]:match('([^;]*); .*')
                            end
                        end
                    end

                    -- Get the final URI out of the Location response header. This should be the original URI that was requested.
                    -- TODO: Consider checking the URI against the original request URI.
                    redirect_uri = "http://127.0.0.1:" .. ngx.var.server_port .. res.headers['Location']

                    -- Make the final call back to the original URI.
                    res, err = httpc:request_uri(redirect_uri, {
                            method = "GET",
                            headers = {
                                ["Cookie"] = cookie_str
                            }
                        })

                    if not res then
                        -- No response, must be an error.
                        ngx.status = 500
                        ngx.say(err)
                        return
                    elseif res.status ~= 200 then
                        -- Not a valid response.
                        -- Use 500 to indicate error.
                        ngx.status = 500
                        ngx.say("Invoking the original URI didn't return the expected result.")
                        return
                    end

                    ngx.status = res.status
                    ngx.say(res.body)
                else
                    -- Response from Keycloak not ok.
                    ngx.say(false)
                end
            end
        }
    }
--- request
GET /t
--- response_body_like
uri: /uri
authorization: Bearer ey.*
cookie: .*
host: 127.0.0.1
user-agent: .*
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 10: Update plugin with `bearer_only=true`.
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
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: Access route w/o bearer token. Should return 401 (Unauthorized).
--- timeout: 10s
--- request
GET /hello
--- error_code: 401
--- response_headers_like
WWW-Authenticate: Bearer realm="apisix"
--- error_log
OIDC introspection failed: No bearer token found in request.



=== TEST 12: Access route with invalid Authorization header value. Should return 400 (Bad Request).
--- timeout: 10s
--- request
GET /hello
--- more_headers
Authorization: foo
--- error_code: 400
--- error_log
OIDC introspection failed: Invalid Authorization header format.



=== TEST 13: Update plugin with ID provider public key, so tokens can be validated locally.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{ "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "scope": "apisix",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                        [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                        [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                        [[-----END PUBLIC KEY-----",
                                    "token_signing_alg_values_expected": "RS256"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 14: Access route with valid token.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9" ..
                        ".eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk" ..
                        "4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCB" ..
                        "jb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqX" ..
                        "RyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 15: Update route URI to '/uri' where upstream endpoint returns request headers in response body.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/uri"
                }]],
                [[{ "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "scope": "apisix",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                        [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                        [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                        [[-----END PUBLIC KEY-----",
                                    "token_signing_alg_values_expected": "RS256"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/uri"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 16: Access route with valid token in `Authorization` header. Upstream should additionally get the token in the `X-Access-Token` header.
--- request
GET /uri HTTP/1.1
--- more_headers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqXRyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w
--- response_body
uri: /uri
authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqXRyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w
host: localhost
x-access-token: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqXRyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w
x-real-ip: 127.0.0.1
--- no_error_log
[error]
--- error_code: 200



=== TEST 17: Update plugin to only use `Authorization` header.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256",
                                "set_access_token_header": true,
                                "access_token_in_authorization_header": true,
                                "set_id_token_header": false,
                                "set_userinfo_header": false
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/uri"
                }]],
                [[{ "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "scope": "apisix",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                        [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                        [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                        [[-----END PUBLIC KEY-----",
                                    "token_signing_alg_values_expected": "RS256",
                                    "access_token_in_authorization_header": true,
                                    "set_id_token_header": false,
                                    "set_userinfo_header": false
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/uri"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 18: Access route with valid token in `Authorization` header. Upstream should not get the additional `X-Access-Token` header.
--- request
GET /uri HTTP/1.1
--- more_headers
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqXRyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w
--- response_body
uri: /uri
authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCBjb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqXRyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7w
host: localhost
x-real-ip: 127.0.0.1
--- no_error_log
[error]
--- error_code: 200



=== TEST 19: Switch route URI back to `/hello`.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{ "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                    [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{ "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "scope": "apisix",
                                    "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                        [[MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ\n]] ..
                                        [[hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==\n]] ..
                                        [[-----END PUBLIC KEY-----",
                                    "token_signing_alg_values_expected": "RS256"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 20: Access route with invalid token. Should return 401.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9" ..
                        ".eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk" ..
                        "4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCB" ..
                        "jb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqX" ..
                        "RyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- error_code: 401
--- error_log
jwt signature verification failed



=== TEST 21: Update route with Keycloak introspection endpoint and public key removed. Should now invoke introspection endpoint to validate tokens.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "course_management",
                                "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                "redirect_uri": "http://localhost:3000",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "realm": "University",
                                "introspection_endpoint_auth_method": "client_secret_post",
                                "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "course_management",
                                    "client_secret": "d1ec69e9-55d2-4109-a3ea-befa071579d5",
                                    "discovery": "http://127.0.0.1:8090/auth/realms/University/.well-known/openid-configuration",
                                    "redirect_uri": "http://localhost:3000",
                                    "ssl_verify": false,
                                    "timeout": 10,
                                    "bearer_only": true,
                                    "realm": "University",
                                    "introspection_endpoint_auth_method": "client_secret_post",
                                    "introspection_endpoint": "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token/introspect"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 22: Obtain valid token and access route with it.
--- config
    location /t {
        content_by_lua_block {
            -- Obtain valid access token from Keycloak using known username and password.
            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:8090/auth/realms/University/protocol/openid-connect/token"
            local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = "grant_type=password&client_id=course_management&client_secret=d1ec69e9-55d2-4109-a3ea-befa071579d5&username=teacher@gmail.com&password=123456",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                })

            -- Check response from keycloak and fail quickly if there's no response.
            if not res then
                ngx.say(err)
                return
            end

            -- Check if response code was ok.
            if res.status == 200 then
                -- Get access token from JSON response body.
                local body = json_decode(res.body)
                local accessToken = body["access_token"]

                -- Access route using access token. Should work.
                uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. body["access_token"]
                    }
                 })

                if res.status == 200 then
                    -- Route accessed successfully.
                    ngx.say(true)
                else
                    -- Couldn't access route.
                    ngx.say(false)
                end
            else
                -- Response from Keycloak not ok.
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 23: Access route with an invalid token.
--- config
    location /t {
        content_by_lua_block {
            -- Access route using a fake access token.
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Authorization"] = "Bearer " .. "fake access token",
                }
             })

            if res.status == 200 then
                ngx.say(true)
            else
                ngx.say(false)
            end
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
OIDC introspection failed: invalid token



=== TEST 24: Check defaults.
--- config
    location /t {
        content_by_lua_block {
            local json = require("t.toolkit.json")
            local plugin = require("apisix.plugins.openid-connect")
            local s = {
                client_id = "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                client_secret = "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                discovery = "http://127.0.0.1:1980/.well-known/openid-configuration",
            }
            local ok, err = plugin.check_schema(s)
            if not ok then
                ngx.say(err)
            end

            ngx.say(json.encode(s))
        }
    }
--- request
GET /t
--- response_body
{"access_token_in_authorization_header":false,"bearer_only":false,"client_id":"kbyuFDidLLm280LIwVFiazOqjO3ty8KH","client_secret":"60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa","discovery":"http://127.0.0.1:1980/.well-known/openid-configuration","introspection_endpoint_auth_method":"client_secret_basic","logout_path":"/logout","realm":"apisix","scope":"openid","set_access_token_header":true,"set_id_token_header":true,"set_userinfo_header":true,"ssl_verify":false,"timeout":3}
--- no_error_log
[error]
