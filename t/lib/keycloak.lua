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

local _M = {}


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
