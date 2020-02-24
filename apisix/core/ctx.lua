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
local log          = require("apisix.core.log")
local tablepool    = require("tablepool")
local get_var      = require("resty.ngxvar").fetch
local get_request  = require("resty.ngxvar").request
local ck           = require "resty.cookie"
local setmetatable = setmetatable
local ffi          = require("ffi")
local C            = ffi.C
local sub_str      = string.sub
local rawset       = rawset
local ngx_var      = ngx.var


ffi.cdef[[
int memcmp(const void *s1, const void *s2, size_t n);
]]


local _M = {version = 0.2}


do
    local var_methods = {
        method = ngx.req.get_method,
        cookie = function () return ck:new() end
    }

    local ngx_var_names = {
        upstream_scheme     = true,
        upstream_host       = true,
        upstream_upgrade    = true,
        upstream_connection = true,
        upstream_uri        = true,
    }

    local mt = {
        __index = function(t, key)
            local val
            local method = var_methods[key]
            if method then
                val = method()

            elseif C.memcmp(key, "cookie_", 7) == 0 then
                local cookie = t.cookie
                if cookie then
                    local err
                    val, err = cookie:get(sub_str(key, 8))
                    if not val then
                        log.warn("failed to fetch cookie value by key: ",
                                 key, " error: ", err)
                    end
                end

            else
                val = get_var(key, t._request)
            end

            if val ~= nil then
                rawset(t, key, val)
            end

            return val
        end,

        __newindex = function(t, key, val)
            if ngx_var_names[key] then
                ngx_var[key] = val
            end

            -- log.info("key: ", key, " new val: ", val)
            rawset(t, key, val)
        end,
    }

function _M.set_vars_meta(ctx)
    local var = tablepool.fetch("ctx_var", 0, 32)
    var._request = get_request()
    setmetatable(var, mt)
    ctx.var = var
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    tablepool.release("ctx_var", ctx.var)
    ctx.var = nil
end

end -- do


return _M
