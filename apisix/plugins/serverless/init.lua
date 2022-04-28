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
local ipairs = ipairs
local pcall = pcall
local loadstring = loadstring
local require = require
local type = type


local phases = {
    "rewrite", "access", "header_filter", "body_filter",
    "log", "before_proxy"
}


return function(plugin_name, priority)
    local core = require("apisix.core")


    local lrucache = core.lrucache.new({
        type = "plugin",
    })

    local schema = {
        type = "object",
        properties = {
            phase = {
                type = "string",
                default = "access",
                enum = phases,
            },
            functions = {
                type = "array",
                items = {type = "string"},
                minItems = 1
            },
        },
        required = {"functions"}
    }

    local _M = {
        version = 0.1,
        priority = priority,
        name = plugin_name,
        schema = schema,
    }

    local function load_funcs(functions)
        local funcs = core.table.new(#functions, 0)

        local index = 1
        for _, func_str in ipairs(functions) do
            local _, func = pcall(loadstring(func_str))
            funcs[index] = func
            index = index + 1
        end

        return funcs
    end

    local function call_funcs(phase, conf, ctx)
        if phase ~= conf.phase then
            return
        end

        local functions = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                   load_funcs, conf.functions)

        for _, func in ipairs(functions) do
            local code, body = func(conf, ctx)
            if code or body then
                return code, body
            end
        end
    end

    function _M.check_schema(conf)
        local ok, err = core.schema.check(schema, conf)
        if not ok then
            return false, err
        end

        local functions = conf.functions
        for _, func_str in ipairs(functions) do
            local func, err = loadstring(func_str)
            if err then
                return false, 'failed to loadstring: ' .. err
            end

            local ok, ret = pcall(func)
            if not ok then
                return false, 'pcall error: ' .. ret
            end
            if type(ret) ~= 'function' then
                return false, 'only accept Lua function,'
                               .. ' the input code type is ' .. type(ret)
            end
        end

        return true
    end

    for _, phase in ipairs(phases) do
        _M[phase] = function (conf, ctx)
            return call_funcs(phase, conf, ctx)
        end
    end

    return _M
end
