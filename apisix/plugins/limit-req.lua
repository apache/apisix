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
local limit_req_new = require("resty.limit.req").new
local core = require("apisix.core")
local plugin_name = "limit-req"
local sleep = ngx.sleep
local ipairs = ipairs

local schema = {
    type = "object",
    properties = {
        rate = { type = "number", minimum = 0 },
        burst = { type = "number", minimum = 0 },
        key = { type = "string",
                enum = { "remote_addr", "server_addr", "http_x_real_ip",
                         "http_x_forwarded_for" },
        },
        headers = { type = "table" },
        parameters = { type = "table" },
        rejected_code = { type = "integer", minimum = 200, default = 503 },
    },
    required = { "rate", "burst" }
}

local _M = {
    version = 0.1,
    priority = 1001, -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.key then
        -- 优先使用key进行限流，如果key不存在则使用 headers 与 parameters 方式进行组合限流
        if (not conf.headers or #conf.headers <= 0) and (not conf.parameters or #conf.parameters) then
            return false, error("key or headers or parameters can not be null")
        end
    end
    return true
end

local function create_limit_obj(conf)
    core.log.info("create new limit-req plugin instance")
    return limit_req_new("plugin-limit-req", conf.rate, conf.burst)
end

function _M.access(conf, ctx)
    local lim, err = core.lrucache.plugin_ctx(plugin_name, ctx,
            create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        return 500
    end

    local prefix = plugin_name .. ctx.conf_type .. ctx.conf_version
    local keyValue = ctx.var[conf.key]
    if not keyValue then
        keyValue = ""
        for _, header in ipairs(conf.headers) do
            local headerValue = ctx.var[header]
            if headerValue then
                keyValue = keyValue .. headerValue
            end
        end

        local args = ngx.req.get_uri_args()
        if args then
            for _, parameter in ipairs(conf.parameters) do
                local parameterValue = args[parameter]
                if parameterValue then
                    keyValue = keyValue .. parameterValue
                end
            end
        end
    end

    local key = prefix + keyValue
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end

return _M
