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
local plugin_name = "repsonse-rewrite"
local ngx         = ngx
local pairs       = pairs
local ipairs      = ipairs


local schema = {
    type = "object",
    properties = {
        headers = {
            description = "new headers for repsonse",
            type = "object",
            minProperties = 1,
        },
        body    =   {
            description = "new body for repsonse",
            type = "string",
        },
    },
    minProperties = 1,
}


local _M = {
    version  = 0.1,
    priority = 1008,
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
        conf.headers_for_jit = {}
        for header_name, header_value in pairs(conf.resp_headers) do
            core.table.insert(conf.headers_for_jit, header_name)
            core.table.insert(conf.headers_for_jit, header_value)
        end 
    end 

    return true
end


do
  
function _M.body_filter(conf, ctx)
    if conf.body then
        ngx.args[1] = conf.body .. "\\n"
    end
end

function _M.header_filter(conf, ctx)
    if conf.body then
        ngx.header.content_length = nil
    end

    if conf.headers_for_jit then
        local field_cnt = #conf.headers_for_jit
        for i = field_cnt,1,-2 do
            ngx.header[conf.headers_for_jit[i-1]] = conf.headers_for_jit[i]
        end
    end
end

end  -- do


return _M
