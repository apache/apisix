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
local core     = require("apisix.core")
local ngx      = ngx
local plugin_name = "request-validation"
local json_decode = require("cjson").decode


local schema = {
    type = "object",
    properties = {
        body_schema = {type = "object"}
    }
}


local _M = {
    version = 0.1,
    priority = 3000,
    type = 'validation',
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.rewrite(conf)
    local body = ngx.req.get_body_data()
    local data, error = json_decode(body)

    if not data then
        core.log.error('failed to decode the body')
        core.response.exit(400)
        return
    end

    local ok, err = core.schema.check(conf.body_schema, data)
    if not ok then
        core.response.exit(400, err)
    end
end


return _M
