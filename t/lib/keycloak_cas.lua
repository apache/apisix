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

local default_opts = {
    idp_uri = "http://127.0.0.1:8080/realms/test/protocol/cas",
    cas_callback_uri = "/cas_callback",
    logout_uri = "/logout",
}

function _M.get_default_opts()
    return default_opts
end

-- Login keycloak and return the login original uri
function _M.login_keycloak(uri, username, password)
    local httpc = http.new()

    local res, err = httpc:request_uri(uri, {method = "GET"})
    if not res then
        return nil, err
    elseif res.status ~= 302 then
        return nil, "login was not redirected to keycloak."
    else
        local cookies = res.headers['Set-Cookie']
        local cookie_str = _M.concatenate_cookies(cookies)

        res, err = httpc:request_uri(res.headers['Location'], {method = "GET"})
        if not res then
            -- No response, must be an error.
            return nil, err
        elseif res.status ~= 200 then
            -- Unexpected response.
            return nil, res.body
        end

        -- From the returned form, extract the submit URI and parameters.
        local uri, params = res.body:match('.*action="(.*)%?(.*)" method="post">')

        -- Substitute escaped ampersand in parameters.
        params = params:gsub("&amp;", "&")

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

        local keycloak_cookie_str = _M.concatenate_cookies(res.headers['Set-Cookie'])

        -- login callback
        local redirect_uri = res.headers['Location']
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
            return nil, "login callback: " ..
                "did not return redirect to original URI."
        end

        cookies = res.headers['Set-Cookie']
        cookie_str = _M.concatenate_cookies(cookies)

        return res, nil, cookie_str, keycloak_cookie_str
    end
end

-- Login keycloak and return the login original uri
function _M.login_keycloak_for_second_sp(uri, keycloak_cookie_str)
    local httpc = http.new()

    local res, err = httpc:request_uri(uri, {method = "GET"})
    if not res then
        return nil, err
    elseif res.status ~= 302 then
        return nil, "login was not redirected to keycloak."
    end

    local cookies = res.headers['Set-Cookie']
    local cookie_str = _M.concatenate_cookies(cookies)

    res, err = httpc:request_uri(res.headers['Location'], {
        method = "GET",
        headers = {
            ["Cookie"] = keycloak_cookie_str
        }
    })
    ngx.log(ngx.INFO, keycloak_cookie_str)

    if not res then
        -- No response, must be an error.
        return nil, err
    elseif res.status ~= 302 then
        -- Not a redirect which we expect.
        return nil, res.body
    end

    -- login callback
    res, err = httpc:request_uri(res.headers['Location'], {
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
        return nil, "login callback: " ..
            "did not return redirect to original URI."
    end

    cookies = res.headers['Set-Cookie']
    cookie_str = _M.concatenate_cookies(cookies)

    return res, nil, cookie_str
end

function _M.logout_keycloak(uri, cookie_str, keycloak_cookie_str)
    local httpc = http.new()

    local res, err = httpc:request_uri(uri, {
        method = "GET",
        headers = {
            ["Cookie"] = cookie_str
        }
    })

    if not res then
        return nil, err
    elseif res.status ~= 302 then
        return nil, "logout was not redirected to keycloak."
    else
        -- keycloak logout
        res, err = httpc:request_uri(res.headers['Location'], {
            method = "GET",
            headers = {
                ["Cookie"] = keycloak_cookie_str
            }
        })
        if not res then
            -- No response, must be an error.
            return nil, err
        elseif res.status ~= 200 then
            return nil, "Logout did not return 200."
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
