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

local function split(text, chunk_size)
    local s = {}
    for i=1, #text, chunk_size do
        s[#s+1] = text:sub(i, i + chunk_size - 1)
    end
    return s
end

local function read_cert(str)
    local t = split(str, 64)
    table.insert(t, 1, "-----BEGIN CERTIFICATE-----")
    table.insert(t, "-----END CERTIFICATE-----")
    return string.format(table.concat(t, "\n"))
end

local sp_private_key = "-----BEGIN PRIVATE KEY-----\n" ..
    "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDCzo92AOThlqsF\n" ..
    "fxqIyA9gHrj3493UxTlhWo15OJnNL1ARNdKL4JFH6nY9sMntkLtaMdY6BYDI2lHC\n" ..
    "v6a1xQSxavkS4kepTFMotj7wmfLXWEY3mFbbITbGUmTQ0yQoJ4Lrii/nQ6Esv20z\n" ..
    "V/mSTJzHLTdcH/lIuksZXKLPnEzue3zqGopvk4ZduvwyRzU0FzPoSYlCLqAEJcx6\n" ..
    "bkulQcZcqSER/0bke/m9eCDt91evDJM1yOHzYuiDZH8trhFwzE+9ms/I/8Svt+tQ\n" ..
    "kAB5EAzfI26VpUWB3oq4eJsoEPEC4UJBsKaZh4a1GA+wbm8ql8EgUr0EsgFZH1Hg\n" ..
    "Gg2m97nLAgMBAAECggEBAJXT0sjadS7/97c5g8nxvMmbt32ItyOfMLusrqSuILSM\n" ..
    "EBO8hpvoczSRorFd2GCr8Ty0meR0ORHBwCJ9zpV821gtQzX/7UfLmSX1zUC11u1D\n" ..
    "SnYV56+PwxYTZtCpo+RyRyIrXR6MiFjnPfDAWAXqgKY8I5jqSotiJMJz2hC9UPoV\n" ..
    "i56tHYXGCjtUAJrvG8FZM46TNL67nQ3ASWb5IH4cOqkgkKAJ/rZLrrMoL/HYpePr\n" ..
    "n2MxlvT+TgdXebxo3rngu3pLRmLsfyV9eCLoOiP/oNAxTEA35EQQlnVfZOIEit8L\n" ..
    "uvBYJYfYuXlxb96nQnOLqO/PrydwpXK9h1NtDvq3K2ECgYEA/i5ebOejoXORkFGx\n" ..
    "DyYwkTczkh7QE328LSUVIiVGh4K1zFeYtj4mYYTeQMbzhlLAf9tGAZyZmvN52/ja\n" ..
    "iFLnI5lObNBooIfAYe3RAzUHGYraY7R1XutdOMjlP9tqjQ55y/xij/tu9qHT4fEz\n" ..
    "aQQPJ8D5sFbB5NgjxC8rlQ/WiLECgYEAxDNss4aMNhvL2+RTda72RMt99BS8PWEZ\n" ..
    "/sdzzvu2zIJYFjBlCZ3Yd3vLhA/0MQXogMIcJofu4u2edZQVFSw4aHfnHFQCr45B\n" ..
    "1QdDhZ8zoludEevgnLdSBzNakEJ63C8AQSkjIck4IaEmW+8G7fswpWGuVDBuHQZm\n" ..
    "PBBcgz84CTsCgYBi8VvSWs0IYPtNyW757azEKk/J1nK605v3mtLCKu5se4YXGBYb\n" ..
    "AtBf75+waYGMTRQf8RQsNnBYr+REq3ctz8+nvNqZYvsHWjCaLj/JVs//slxWqX1y\n" ..
    "yH3OR+1tURUF+ZeRvxoC4CYOnWnkLscLXwgjOmw3p13snfI2QQJfEP460QKBgCzD\n" ..
    "LsGmqMaPgOsiJIhs6nK3mnzdXjUCulOOXbWTaBkwg7hMQkD3ajOYYs42dZfZqTn3\n" ..
    "D0UbLj1HySc6KbUy6YusD2Y/JH25DvvzNEyADd+01xkHn68hg+1wofDXugASGRTE\n" ..
    "tec3aT8C7SV8WzBgZrDUoFlE01p740dA1Fp9SeORAoGBAIEa6LBIXuxb13xdOPDQ\n" ..
    "FLaOQvmDCZeEwy2RAIOhG/1KGv+HYoCv0mMb4UXE1d65TOOE9QZLGUXksFfPc/ya\n" ..
    "OP1vdjF/HN3DznxQ421GdPDYVIfp7edxZstNtGMYcR/SBwoIcvwaA5c2woMHbeju\n" ..
    "+rbxDQL4gIT1lqn71w/8uoIJ\n" ..
    "-----END PRIVATE KEY-----"

local sp_cert = "-----BEGIN CERTIFICATE-----\n" ..
    "MIIDgjCCAmqgAwIBAgIUOnf+MXKVU2zfIVaPz5dl0NTwPM4wDQYJKoZIhvcNAQEN\n" ..
    "BQAwUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRcwFQYDVQQKDA5sdWEt\n" ..
    "cmVzdHktc2FtbDEZMBcGA1UEAwwQc2VydmljZS1wcm92aWRlcjAgFw0xOTA1MDgw\n" ..
    "MTIyMDZaGA8yMTE4MDQxNDAxMjIwNlowUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgM\n" ..
    "BVRleGFzMRcwFQYDVQQKDA5sdWEtcmVzdHktc2FtbDEZMBcGA1UEAwwQc2Vydmlj\n" ..
    "ZS1wcm92aWRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLOj3YA\n" ..
    "5OGWqwV/GojID2AeuPfj3dTFOWFajXk4mc0vUBE10ovgkUfqdj2wye2Qu1ox1joF\n" ..
    "gMjaUcK/prXFBLFq+RLiR6lMUyi2PvCZ8tdYRjeYVtshNsZSZNDTJCgnguuKL+dD\n" ..
    "oSy/bTNX+ZJMnMctN1wf+Ui6Sxlcos+cTO57fOoaim+Thl26/DJHNTQXM+hJiUIu\n" ..
    "oAQlzHpuS6VBxlypIRH/RuR7+b14IO33V68MkzXI4fNi6INkfy2uEXDMT72az8j/\n" ..
    "xK+361CQAHkQDN8jbpWlRYHeirh4mygQ8QLhQkGwppmHhrUYD7BubyqXwSBSvQSy\n" ..
    "AVkfUeAaDab3ucsCAwEAAaNQME4wHQYDVR0OBBYEFPbRiK9OxGCZeNUViinNQ4P5\n" ..
    "ZOf0MB8GA1UdIwQYMBaAFPbRiK9OxGCZeNUViinNQ4P5ZOf0MAwGA1UdEwQFMAMB\n" ..
    "Af8wDQYJKoZIhvcNAQENBQADggEBAD0MvA3mk+u3CBDFwPtT9tI8HPSaYXS0HZ3E\n" ..
    "VXe4WcU3PYFpZzK0x6qr+a7mB3tbpHYXl49V7uxcIOD2aHLvKonKRRslyTiw4UvL\n" ..
    "OhSSByrArUGleI0wyr1BXAJArippiIhqrTDybvPpFC45x45/KtrckeM92NOlttlQ\n" ..
    "yd2yW0qSd9gAnqkDu2kvjLlGh9ZYnT+yHPjUuWcxDL66P3za6gc+GhVOtsOemdYN\n" ..
    "AErhuxiGVNHrtq2dfSedqcxtCpavMYzyGhqzxr9Lt43fpQeXeS/7JVFoC2y9buyO\n" ..
    "z9HIbQ6/02HIoenDoP3xfqvAY1emixgbV4iwm3SWzG8pSTxvwuM=\n" ..
    "-----END CERTIFICATE-----"

local idp_uri = "http://127.0.0.1:8080/realms/test/protocol/saml"

local default_opts = {
    idp_uri = idp_uri,
    login_callback_uri = "/acs",
    logout_uri = "/logout",
    logout_callback_uri = "/sls",
    logout_redirect_uri = "/logout_ok",
    sp_cert = sp_cert,
    sp_private_key = sp_private_key,
}

local function get_realm_cert()
    local http = require "resty.http"
    local httpc = http.new()
    local uri = "http://127.0.0.1:8080/realms/test/protocol/saml/descriptor"
    local res, err = httpc:request_uri(uri, { method = "GET" })
    if err then
        ngx.log(ngx.ERR, err)
        ngx.exit(500)
    end

    local cert = res.body:match("<ds:X509Certificate>(.-)</ds:X509Certificate>")
    return read_cert(cert)
end

function _M.get_default_opts()
    if default_opts.idp_cert == nil then
        default_opts.idp_cert = get_realm_cert()
    end
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

-- Logout keycloak and return the logout_redirect_uri
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
        elseif res.status ~= 302 then
            -- Not a redirect which we expect.
            return nil, "Logout did not return redirect to redirect URI."
        end

        -- logout callback
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
            return nil, "logout callback: " ..
                "did not return redirect to logout redirect URI."
        end

        return res, nil
    end
end

-- Logout keycloak and return the logout_redirect_uri
function _M.single_logout(uri, cookie_str, cookie_str2, keycloak_cookie_str)
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
    end

    -- logout request from sp1 to keycloak
    res, err = httpc:request_uri(res.headers['Location'], {
        method = "GET",
        headers = {
            ["Cookie"] = keycloak_cookie_str
        }
    })
    if not res then
        -- No response, must be an error.
        return nil, err
    elseif res.status ~= 302 then
        -- Not a redirect which we expect.
        return nil, "Logout did not return redirect to redirect URI."
    end

    -- logout callback to sp2
    res, err = httpc:request_uri(res.headers['Location'], {
        method = "GET",
        headers = {
            ["Cookie"] = cookie_str2
        }
    })

    if not res then
        -- No response, must be an error.
        return nil, err
    elseif res.status ~= 302 then
        -- Not a redirect which we expect.
        return nil, "logout callback: " ..
        "did not return redirect to logout redirect URI."
    end

    -- logout response from sp2 to keycloak
    res, err = httpc:request_uri(res.headers['Location'], {
        method = "GET",
        headers = {
            ["Cookie"] = keycloak_cookie_str
        }
    })
    if not res then
        -- No response, must be an error.
        return nil, err
    elseif res.status ~= 302 then
        -- Not a redirect which we expect.
        return nil, "Logout did not return redirect to redirect URI."
    end

    -- logout response from keycloak to sp1
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
        return nil, "logout callback: " ..
        "did not return redirect to logout redirect URI."
    end

    return res, nil
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
