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
local core        = require("apisix.core")
local expr        = require("resty.expr.v1")
local plugin_name = "response-rewrite"
local ngx         = ngx
local pairs       = pairs
local type        = type


local schema = {
    type = "object",
    properties = {
        headers = {
            description = "new headers for response",
            type = "object",
            minProperties = 1,
        },
        body = {
            description = "new body for response",
            type = "string",
        },
        body_base64 = {
            description = "whether new body for response need base64 decode before return",
            type = "boolean",
            default = false,
        },
        status_code = {
            description = "new status code for response",
            type = "integer",
            minimum = 200,
            maximum = 598,
        },
        vars = {
            type = "array",
            items = {
                description = "Nginx builtin variable name and value",
                type = "array",
                maxItems = 4,
                minItems = 2,
            },
        },
    },
    minProperties = 1,
    additionalProperties = false,
}


local _M = {
    version  = 0.1,
    priority = 899,
    name     = plugin_name,
    schema   = schema,
}

local function vars_matched(conf, ctx)
    if not conf.vars then
        return true
    end

    if not conf.response_expr then
        local response_expr, _ = expr.new(conf.vars)
        conf.response_expr = response_expr
    end

    local match_result = conf.response_expr:eval(ctx.var)

    return match_result
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.headers then
        for field, value in pairs(conf.headers) do
            if type(field) ~= 'string' then
                return false, 'invalid type as header field'
            end

            if type(value) ~= 'string' and type(value) ~= 'number' then
                return false, 'invalid type as header value'
            end

            if #field == 0 then
                return false, 'invalid field length in header'
            end
        end
    end

    if conf.body_base64 then
        local body = ngx.decode_base64(conf.body)
        if not body then
            return  false, 'invalid base64 content'
        end
    end

    if conf.vars then
        local ok, err = expr.new(conf.vars)
        if not ok then
            return false, "failed to validate the 'vars' expression: " .. err
        end
    end

    return true
end


do

function _M.body_filter(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.body then

        if conf.body_base64 then
            ngx.arg[1] = ngx.decode_base64(conf.body)
        else
            ngx.arg[1] = conf.body
        end

        ngx.arg[2] = true
    end
end

function _M.header_filter(conf, ctx)
    ctx.response_rewrite_matched = vars_matched(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.status_code then
        ngx.status = conf.status_code
    end

    if conf.body then
        core.response.clear_header_as_body_modified()
    end

    if not conf.headers then
        return
    end

    --reform header from object into array, so can avoid use pairs, which is NYI
    if not conf.headers_arr then
        conf.headers_arr = {}

        for field, value in pairs(conf.headers) do
            core.table.insert_tail(conf.headers_arr, field, value)
        end
    end

    local field_cnt = #conf.headers_arr
    for i = 1, field_cnt, 2 do
        ngx.header[conf.headers_arr[i]] = conf.headers_arr[i+1]
    end
end

end  -- do


return _M
