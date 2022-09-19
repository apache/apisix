--
---- Licensed to the Apache Software Foundation (ASF) under one or more
---- contributor license agreements.  See the NOTICE file distributed with
---- this work for additional information regarding copyright ownership.
---- The ASF licenses this file to You under the Apache License, Version 2.0
---- (the "License"); you may not use this file except in compliance with
---- the License.  You may obtain a copy of the License at
----
----     http://www.apache.org/licenses/LICENSE-2.0
----
---- Unless required by applicable law or agreed to in writing, software
---- distributed under the License is distributed on an "AS IS" BASIS,
---- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
---- See the License for the specific language governing permissions and
---- limitations under the License.
----
local core = require("apisix.core")
local http = require("resty.http")
local ngx = ngx
local type = type
local table = table
local string = string

local CAS_REQUEST_URI = "CAS_REQUEST_URI"
local COOKIE_NAME = "CAS_SESSION"
local COOKIE_PARAMS = "; Path=/; HttpOnly"
local SESSION_LIFETIME = 3600
local STORE_NAME = "cas_sessions"

local store = ngx.shared[STORE_NAME]


local plugin_name = "cas-auth"
local schema = {
    type = "object",
    properties = {
        idp_uri = {type = "string"},
        cas_callback_uri = {type = "string"},
        logout_uri = {type = "string"},
    },
    required = {
        "idp_uri", "cas_callback_uri", "logout_uri"
    }
}

local _M = {
    version = 0.1,
    priority = 2597,
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function to_table(v)
    if v == nil then
        return {}
    elseif type(v) == "table" then
        return v
    else
        return {v}
    end
end

local function set_cookie(cookie_str)
    local h = to_table(ngx.header['Set-Cookie'])
    table.insert(h, cookie_str)
    ngx.header['Set-Cookie'] = h
end

local function uri_without_ticket(conf)
    return ngx.var.scheme .. "://" .. ngx.var.host .. ":" ..
        ngx.var.server_port .. conf.cas_callback_uri
end

local function get_session_id()
    return ngx.var["cookie_" .. COOKIE_NAME]
end

local function set_our_cookie(name, val)
    set_cookie(name .. "=" .. val .. COOKIE_PARAMS)
end

local function first_access(conf)
    local login_uri = conf.idp_uri .. "/login?" ..
        ngx.encode_args({ service = uri_without_ticket(conf) })
    ngx.log(ngx.INFO, "first access: ", login_uri,
        ", cookie: ", ngx.var.http_cookie, ", request_uri: ", ngx.var.request_uri)
    set_our_cookie(CAS_REQUEST_URI, ngx.var.request_uri)
    ngx.redirect(login_uri, ngx.HTTP_MOVED_TEMPORARILY)
end

local function with_session_id(conf, session_id)
    -- does the cookie exist in our store?
    local user = store:get(session_id);
    ngx.log(ngx.INFO, "ticket=", session_id, ", user=", user)
    if user == nil then
        set_our_cookie(COOKIE_NAME, "deleted; Max-Age=0")
        first_access(conf)
    else
        -- refresh the TTL
        store:set(session_id, user, SESSION_LIFETIME)
    end
end

local function set_store_and_cookie(session_id, user)
    -- place cookie into cookie store
    local success, err, forcible = store:add(session_id, user, SESSION_LIFETIME)
    if success then
        if forcible then
            ngx.log(ngx.INFO, "CAS cookie store is out of memory")
        end
        set_our_cookie(COOKIE_NAME, session_id)
    else
        if err == "no memory" then
            ngx.log(ngx.EMERG, "CAS cookie store is out of memory")
        elseif err == "exists" then
            ngx.log(ngx.ERR, "Same CAS ticket validated twice, this should never happen!")
        end
    end
    return success
end

local function validate(conf, ticket)
    -- send a request to CAS to validate the ticket
    local httpc = http.new()
    local res, err = httpc:request_uri(conf.idp_uri ..
        "/serviceValidate", { query = { ticket = ticket, service = uri_without_ticket(conf) } })

    if res and res.status == ngx.HTTP_OK and res.body ~= nil then
        if string.find(res.body, "<cas:authenticationSuccess>") then
            local m = ngx.re.match(res.body, "<cas:user>(.*?)</cas:user>");
            if m then
                return m[1]
            end
        else
            ngx.log(ngx.INFO, "CAS serviceValidate failed: " .. res.body)
        end
    else
        ngx.log(ngx.ERR, "validate ticket failed: res=", res, ", err=", err)
    end
    return nil
end

local function validate_with_cas(conf, ticket)
    local user = validate(conf, ticket)
    if user and set_store_and_cookie(ticket, user) then
        local request_uri = ngx.var["cookie_" .. CAS_REQUEST_URI]
        set_our_cookie(CAS_REQUEST_URI, "deleted; Max-Age=0")
        ngx.log(ngx.INFO, "ticket: ", ticket,
            ", cookie: ", ngx.var.http_cookie, ", request_uri: ", request_uri, ", user=", user)
        ngx.redirect(request_uri, ngx.HTTP_MOVED_TEMPORARILY)
    else
        return ngx.HTTP_UNAUTHORIZED, {message = "invalid ticket"}
    end
end

local function logout(conf)
    local session_id = get_session_id()
    if session_id == nil then
        return ngx.HTTP_UNAUTHORIZED
    end

    ngx.log(ngx.INFO, "logout: ticket=", session_id, ", cookie=", ngx.var.http_cookie)
    store:delete(session_id)
    set_our_cookie(COOKIE_NAME, "deleted; Max-Age=0")

    ngx.redirect(conf.idp_uri .. "/logout")
end

function _M.access(conf, ctx)
    local method = ngx.req.get_method()
    local uri = ngx.var.uri

    if method == "GET" and uri == conf.logout_uri then
        return logout(conf)
    elseif method == "POST" and uri == conf.cas_callback_uri then
        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        local ticket = data:match("<samlp:SessionIndex>(.*)</samlp:SessionIndex>")
        if ticket == nil then
            return 400, {message = "invalid logout request from IdP, no ticket"}
        end
        ngx.log(ngx.INFO, "Back-channel logout (SLO) from IdP: LogoutRequest: ", data)
        local session_id = ticket
        local user = store:get(session_id);
        if user then
            store:delete(session_id)
            ngx.log(ngx.INFO, "SLO: user=", user, ", tocket=", ticket)
        end
    else
        local session_id = get_session_id()
        if session_id ~= nil then
            return with_session_id(conf, session_id)
        end

        local ticket = ngx.var.arg_ticket
        if ticket ~= nil and uri == conf.cas_callback_uri then
            return validate_with_cas(conf, ticket)
        else
            first_access(conf)
        end
    end
end

return _M
