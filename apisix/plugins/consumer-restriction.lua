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
local ipairs    = ipairs
local core      = require("apisix.core")
local ngx       = ngx
local schema = {
    type = "object",
    properties = {
        type = {
            type = "string",
            enum = {"consumer_name", "service_id", "route_id"},
            default = "consumer_name"
        },
        blacklist = {
            type = "array",
            minItems = 1,
            items = {type = "string"}
        },
        whitelist = {
            type = "array",
            minItems = 1,
            items = {type = "string"}
        },
        allowed_by_methods = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    user = {
                        type = "string"
                    },
                    methods = {
                        type = "array",
                        minItems = 1,
                        items = core.schema.method_schema,
                    }
                }
            }
        },
        rejected_code = {type = "integer", minimum = 200, default = 403}
    },
    anyOf = {
        {required = {"blacklist"}},
        {required = {"whitelist"}},
        {required = {"allowed_by_methods"}}
    },
}

local plugin_name = "consumer-restriction"

local _M = {
    version = 0.1,
    priority = 2400,
    name = plugin_name,
    schema = schema,
}

local fetch_val_funcs = {
    ["route_id"] = function(ctx)
        return ctx.route_id
    end,
    ["service_id"] = function(ctx)
        return ctx.service_id
    end,
    ["consumer_name"] = function(ctx)
        return ctx.consumer_name
    end
}

local function is_include(value, tab)
    for k,v in ipairs(tab) do
        if v == value then
            return true
        end
    end
    return false
end

local function is_method_allowed(allowed_methods, method, user)
    for _, value in ipairs(allowed_methods) do
        if value.user == user then
            for _, allowed_method in ipairs(value.methods) do
                if allowed_method == method then
                    return true
                end
            end
            return false
        end
    end
    return true
end

local function reject(conf)
    return conf.rejected_code, { message = "The " .. conf.type .. " is forbidden." }
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
   if not ok then
        return false, err
   end
   return true
end

function _M.access(conf, ctx)
    local value = fetch_val_funcs[conf.type](ctx)
    local method = ngx.req.get_method()

    if not value then
        return 401, { message = "Missing authentication or identity verification."}
    end
    core.log.info("value: ", value)

    local block = false
    local whitelisted = false

    if conf.blacklist and #conf.blacklist > 0 then
        if is_include(value, conf.blacklist) then
            return reject(conf)
        end
    end

    if conf.whitelist and #conf.whitelist > 0 then
        whitelisted = is_include(value, conf.whitelist)
        if not whitelisted then
            block = true
        end
    end

    if conf.allowed_by_methods and #conf.allowed_by_methods > 0 and not whitelisted then
        if not is_method_allowed(conf.allowed_by_methods, method, value) then
            block = true
        end
    end

    if block then
        return reject(conf)
    end
end

return _M
