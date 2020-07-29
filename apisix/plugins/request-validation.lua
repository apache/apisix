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
local core          = require("apisix.core")
local plugin_name   = "request-validation"
local ngx           = ngx
local io           = io

local schema = {
    type = "object",
    properties = {
        body_schema = {type = "object"},
        header_schema = {type = "object"}
    },
    anyOf = {
        {required = {"body_schema"}},
        {required = {"header_schema"}}
    }
}


local _M = {
    version = 0.1,
    priority = 2800,
    type = 'validation',
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.body_schema then
        ok, err = core.schema.valid(conf.body_schema)
        if not ok then
            return false, err
        end
    end

    if conf.header_schema then
        ok, err = core.schema.valid(conf.header_schema)
        if not ok then
            return false, err
        end
    end

    return true, nil
end


function _M.rewrite(conf)
    local headers = ngx.req.get_headers()

    if conf.header_schema then
        local ok, err = core.schema.check(conf.header_schema, headers)
        if not ok then
            core.log.error("req schema validation failed", err)
            core.response.exit(400, err)
        end
    end

    if conf.body_schema then
        ngx.req.read_body()
        local req_body, error
        local body = ngx.req.get_body_data()

        if not body then
            local filename = ngx.req.get_body_file()
            if not filename then
                return core.response.exit(500)
            end
            local fd = io.open(filename, 'rb')
            if not fd then
                return core.response.exit(500)
            end
            body = fd:read('*a')
        end

        if headers["content-type"] == "application/x-www-form-urlencoded" then
            req_body, error = ngx.decode_args(body)
        else -- JSON as default
            req_body, error = core.json.decode(body)
        end

        if not req_body then
          core.log.error('failed to decode the req body', error)
          return core.response.exit(400, error)
        end

        local ok, err = core.schema.check(conf.body_schema, req_body)
        if not ok then
          core.log.error("req schema validation failed", err)
          return core.response.exit(400, err)
        end
    end
end

return _M
