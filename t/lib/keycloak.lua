--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local http = require "resty.http"
local cjson = require "cjson.safe"

local _M = {}

-- Base URL and fixtures matching the CI Keycloak provisioned by
-- ci/pod/keycloak/kcadm_configure_university.sh.
local KEYCLOAK_BASE = "http://127.0.0.1:8080"
local REALM_BASE = KEYCLOAK_BASE .. "/admin/realms/University"


-- Fetch an admin access token from the master realm.
function _M.get_admin_token()
    local httpc = http.new()
    local res, err = httpc:request_uri(
        KEYCLOAK_BASE .. "/realms/master/protocol/openid-connect/token", {
            method = "POST",
            body = "grant_type=password&client_id=admin-cli" ..
                   "&username=admin&password=admin",
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded"
            }
        })
    if not res or res.status ~= 200 then
        return nil, "admin token request failed: " ..
                    (res and res.status or err)
    end
    return cjson.decode(res.body).access_token
end


-- Set the course_management client's backchannel logout URL and the
-- "session required" flag (whether logout tokens carry a sid claim).
function _M.set_backchannel_logout(token, url, session_required)
    local httpc = http.new()
    local res, err = httpc:request_uri(
        REALM_BASE .. "/clients?clientId=course_management", {
            headers = { ["Authorization"] = "Bearer " .. token }
        })
    if not res or res.status ~= 200 then
        return nil, "client lookup failed: " .. (res and res.status or err)
    end
    local client = cjson.decode(res.body)[1]
    client.attributes = client.attributes or {}
    client.attributes["backchannel.logout.url"] = url
    client.attributes["backchannel.logout.session.required"] =
        session_required and "true" or "false"
    res, err = httpc:request_uri(REALM_BASE .. "/clients/" .. client.id, {
        method = "PUT",
        body = cjson.encode(client),
        headers = {
            ["Authorization"] = "Bearer " .. token,
            ["Content-Type"] = "application/json"
        }
    })
    if not res or res.status >= 300 then
        return nil, "client update failed: " .. (res and res.status or err)
    end
    return true
end


-- Make the caller's next admin logout deliver its back-channel logout token
-- deterministically, working around two observed Keycloak behaviors:
-- 1. A logout-all over several live sessions has been observed to deliver a
--    logout token for only one of them; purging the user's leftover sessions
--    first means the session the caller creates next is the only one, so its
--    token is the one delivered.
-- 2. Keycloak pools its connection to the logout URL and does not retry a
--    POST whose pooled socket died with a restarted gateway; a throwaway
--    login/logout of the student user absorbs any stale socket.
function _M.prime_backchannel_logout(uri)
    local token, terr = _M.get_admin_token()
    if not token then
        return nil, terr
    end
    local ok, perr = _M.logout_user(token, "teacher@gmail.com")
    if not ok then
        return nil, perr
    end

    local httpc = http.new()
    local res, err = _M.login_keycloak(uri, "student@gmail.com", "123456")
    if err then
        return nil, "prime login failed: " .. err
    end
    local cookie_str = _M.concatenate_cookies(res.headers['Set-Cookie'])
    local base = uri:match("^(https?://[^/]+)")
    res, err = httpc:request_uri(base .. res.headers['Location'], {
        method = "GET",
        headers = { ["Cookie"] = cookie_str }
    })
    if not res or res.status ~= 200 then
        return nil, "prime code exchange failed: " ..
                    (res and res.status or err)
    end
    local lerr
    ok, lerr = _M.logout_user(token, "student@gmail.com")
    if not ok then
        return nil, lerr
    end
    return true
end


-- Log the user out through the admin API; Keycloak then delivers
-- back-channel logout tokens to the registered clients.
function _M.logout_user(token, username)
    local httpc = http.new()
    local res, err = httpc:request_uri(
        REALM_BASE .. "/users?username=" .. username .. "&exact=true", {
            headers = { ["Authorization"] = "Bearer " .. token }
        })
    if not res or res.status ~= 200 then
        return nil, "user lookup failed: " .. (res and res.status or err)
    end
    local user = cjson.decode(res.body)[1]
    res, err = httpc:request_uri(REALM_BASE .. "/users/" .. user.id .. "/logout", {
        method = "POST",
        headers = { ["Authorization"] = "Bearer " .. token }
    })
    if not res or res.status >= 300 then
        return nil, "admin logout failed: " .. (res and res.status or err)
    end
    return true
end


-- Request APISIX and redirect to keycloak,
-- Login keycloak and return the res of APISIX
function _M.login_keycloak(uri, username, password)
    local httpc = http.new()

    local res, err = httpc:request_uri(uri, {method = "GET"})
    if not res then
        return nil, err
    elseif res.status ~= 302 then
        -- Not a redirect which we expect.
        -- Use 500 to indicate error.
        return nil, "Initial request was not redirected to ID provider authorization endpoint."
    else
        -- Extract cookies. Important since OIDC module tracks state with a session cookie.
        local cookies = res.headers['Set-Cookie']

        -- Concatenate cookies into one string as expected when sent in request header.
        local cookie_str = _M.concatenate_cookies(cookies)

        -- Call authorization endpoint we were redirected to.
        -- Note: This typically returns a login form which is the case here for Keycloak as well.
        -- However, how we process the form to perform the login is specific to Keycloak and
        -- possibly even the version used.
        res, err = httpc:request_uri(res.headers['Location'], {method = "GET"})
        if not res then
            -- No response, must be an error.
            return nil, err
        elseif res.status ~= 200 then
            -- Unexpected response.
            return nil, res.body
        end

        -- Check if response code was ok.
        if res.status ~= 200 then
            return nil, "unexpected status " .. res.status
        end

        -- From the returned form, extract the submit URI and parameters.
        local uri, params = res.body:match('.*action="(.*)%?(.*)" method="post">')

        -- Substitute escaped ampersand in parameters.
        params = params:gsub("&amp;", "&")

        -- Get all cookies returned. Probably not so important since not part of OIDC specification.
        local auth_cookies = res.headers['Set-Cookie']

        -- Concatenate cookies into one string as expected when sent in request header.
        local auth_cookie_str = _M.concatenate_cookies(auth_cookies)

        -- Invoke the submit URI with parameters and cookies, adding username
        -- and password in the body.
        -- Note: Username and password are specific to the Keycloak Docker image used.
        res, err = httpc:request_uri(uri .. "?" .. params, {
                method = "POST",
                body = "username=" .. username .. "&password=" .. password,
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                    ["Cookie"] = auth_cookie_str
                }
            })
        if not res then
            -- No response, must be an error.
            return nil, err
        elseif res.status ~= 302 then
            -- Not a redirect which we expect.
            return nil, "Login form submission did not return redirect to redirect URI."
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
            return nil, err
        elseif res.status ~= 302 then
            -- Not a redirect which we expect.
            return nil, "Invoking redirect URI with authorization code" ..
                "did not return redirect to original URI."
        end

        return res, nil
    end
end


-- Concatenate cookies into one string as expected when sent in request header.
function _M.concatenate_cookies(cookies)
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

    return cookie_str, nil
end


return _M
