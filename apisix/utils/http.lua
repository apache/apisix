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

--- Outbound HTTP client selection.
-- Shared by any module that makes outbound HTTP calls, so the choice between
-- `ngx_http_ffi_client` and `lua-resty-http` is made in one place rather than
-- per plugin. The caller decides where the preference comes from (its own
-- config key) and passes the name in.

local core = require("apisix.core")
local pcall = pcall
local require = require
local tostring = tostring
local type = type

local FFI_CLIENT = "ngx_http_ffi_client"
local LUA_RESTY_HTTP = "lua-resty-http"

-- the client name used in configuration is not the module name
local CLIENT_MODULES = {
    [FFI_CLIENT] = "resty.ngx_http_ffi_client",
    [LUA_RESTY_HTTP] = "resty.http",
}

local loaded = {}


local _M = {
    version = 0.1,
    FFI_CLIENT = FFI_CLIENT,
    LUA_RESTY_HTTP = LUA_RESTY_HTTP,
    DEFAULT_CLIENT = FFI_CLIENT,
}


--- Schema fragment for a client-name config field.
-- Callers embed this in their own attribute schema so every module validates
-- the name the same way.
_M.client_schema = {
    type = "string",
    enum = {FFI_CLIENT, LUA_RESTY_HTTP},
    default = FFI_CLIENT,
}


--- Load the module for a client name.
-- `ngx_http_ffi_client` is a C client with the same object API as
-- lua-resty-http and around half its outbound CPU cost, and it exists only
-- when the gateway runtime was built with the module. A name that cannot be
-- loaded is an error, never a silent switch to the other client.
-- Cached per name once loaded, so a failure is retried rather than remembered.
local function load_client(name)
    local cached = loaded[name]
    if cached then
        return cached
    end

    local module_name = CLIENT_MODULES[name]
    if not module_name then
        return nil, "unknown http client: " .. tostring(name)
    end

    local ok, mod = pcall(require, module_name)
    if not ok or type(mod) ~= "table" then
        core.log.error(module_name, " is not available: ", mod)
        return nil, module_name .. " is not available: " .. tostring(mod)
    end

    -- Cosockets have their names resolved by apisix/patch.lua, which routes
    -- them through core.resolver and so honours dns_resolver, /etc/hosts and
    -- the search domains. The C client dials from C and never touches a
    -- cosocket, so without this it would see only nginx's `resolver`. Handing
    -- it the same resolver keeps every outbound name on one set of rules.
    -- A client too old to take one is an error rather than a client quietly
    -- resolving names by different rules than the rest of the gateway.
    if name == FFI_CLIENT then
        if type(mod.set_resolver) ~= "function" then
            core.log.error(module_name, " does not support set_resolver, ",
                           "the runtime is older than the pinned one")
            return nil, module_name .. " does not support set_resolver, "
                        .. "the runtime is older than the pinned one"
        end

        mod.set_resolver(core.resolver.parse_domain)
    end

    loaded[name] = mod

    return mod
end


--- Create an HTTP client.
-- @tparam string|nil name client name; defaults to DEFAULT_CLIENT
-- @treturn table|nil the client
-- @treturn string|nil error message
function _M.new(name)
    name = name or _M.DEFAULT_CLIENT

    local mod, err = load_client(name)
    if not mod then
        return nil, err
    end

    -- The Lua half of `ngx_http_ffi_client` loads even when the C module is
    -- not compiled into the runtime; new() is what reports that.
    return mod.new()
end


return _M
