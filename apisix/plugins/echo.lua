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
local core = require("apisix.core")
local pairs       = pairs
local type        = type
local ngx         = ngx


local schema = {
    type = "object",
    properties = {
        before_body = {
            description = "body before the filter phase.",
            type = "string"
        },
        body = {
            description = "body to replace upstream response.",
            type = "string"
        },
        after_body = {
            description = "body after the modification of filter phase.",
            type = "string"
        },
        headers = {
            description = "new headers for repsonse",
            type = "object",
            minProperties = 1,
        },
        auth_value = {
            description = "auth value",
            type = "string"
        }
    },
    anyOf = {
        {required = {"before_body"}},
        {required = {"body"}},
        {required = {"after_body"}}
    },
    minProperties = 1
}

local plugin_name = "echo"

local _M = {
    version = 0.1,
    priority = 412,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    if conf.headers then
        conf.headers_arr = {}

        for field, value in pairs(conf.headers) do
            if type(field) == 'string'
                    and (type(value) == 'string' or type(value) == 'number') then
                if #field == 0 then
                    return false, 'invalid field length in header'
                end
                core.table.insert(conf.headers_arr, field)
                core.table.insert(conf.headers_arr, value)
            else
                return false, 'invalid type as header value'
            end
        end
    end

    return core.schema.check(schema, conf)
end

function _M.body_filter(conf, ctx)
    if conf.body then
        ngx.arg[1] = conf.body
    end

    if conf.before_body then
        ngx.arg[1] = conf.before_body ..  ngx.arg[1]
    end

    if conf.after_body then
        ngx.arg[1] = ngx.arg[1] .. conf.after_body
    end
    ngx.arg[2] = true
end

function _M.access(conf, ctx)
    local value = core.request.header(ctx, "Authorization")

    if value ~= conf.auth_value then
        return 401, "unauthorized body"
    end

end

function _M.header_filter(conf, ctx)
    if conf.headers_arr then
        local field_cnt = #conf.headers_arr
        for i = 1, field_cnt, 2 do
            ngx.header[conf.headers_arr[i]] = conf.headers_arr[i+1]
        end
    end
end

return _M
