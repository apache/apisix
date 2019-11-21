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
local plugin_name = "response-rewrite"
local ngx         = ngx
local pairs       = pairs
local type        = type


local schema = {
    type = "object",
    properties = {
        headers = {
            description = "new headers for repsonse",
            type = "object",
            minProperties = 1,
        },
        body = {
            description = "new body for repsonse",
            type = "string",
        },
        status_code = {
            description = "new status code for repsonse",
            type = "integer",
            minimum = 200,
            maximum = 598,
        }
    },
    minProperties = 1,
}


local _M = {
    version  = 0.1,
    priority = 899,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    --reform header from object into array, so can avoid use pairs, which is NYI
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

    return true
end


do

function _M.body_filter(conf, ctx)
    if conf.body then
        ngx.arg[1] = conf.body
        ngx.arg[2] = true
    end
end

function _M.header_filter(conf, ctx)
    if conf.status_code then
        ngx.status = conf.status_code
    end

    if conf.body then
        ngx.header.content_length = nil
        -- in case of upstream content is compressed content
        ngx.header.content_encoding = nil
    end

    if conf.headers_arr then
        local field_cnt = #conf.headers_arr
        for i = 1, field_cnt, 2 do
            ngx.header[conf.headers_arr[i]] = conf.headers_arr[i+1]
        end
    end
end

end  -- do


return _M
