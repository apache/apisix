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
local json_decode   = require("cjson").decode
local ngx           = ngx
local lower         = string.lower


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
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf)
    local headers = ngx.req.get_headers()
    local body = {}

    if conf.body_schema.properties.header_schema then
        local ok, err = core.schema.check(conf.header_schema, headers)
        if not ok then
            core.log.error("req schema validation failed", err)
            core.response.exit(400, err)
        end
    end

    if not conf.body_schema.properties.body_schema then
        ngx.req.read_body()
        body = ngx.req.get_body_data()

        if headers["content-type"] then
            if headers["content-type"] == "application/json" then
                local data, error = json_decode(body)

                if not data then
                  core.log.error('failed to decode the req body', error)
                  core.response.exit(400)
                  return
                end

                local ok, err = core.schema.check(conf.body_schema, data)
                if not ok then
                  core.log.error("req schema validation failed", err)
                  core.response.exit(400, err)
                end
              end
        else
          core.response.exit(400, err)
        end
    end
end


return _M
