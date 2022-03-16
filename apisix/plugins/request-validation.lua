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

local schema = {
    type = "object",
    properties = {
        header_schema = {type = "object"},
        body_schema = {type = "object"},
        rejected_code = {type = "integer", minimum = 200, maximum = 599, default = 400},
        rejected_msg = {type = "string", minLength = 1, maxLength = 256}
    },
    anyOf = {
        {required = {"header_schema"}},
        {required = {"body_schema"}}
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


function _M.rewrite(conf, ctx)
    local headers = core.request.headers(ctx)

    if conf.header_schema then
        local ok, err = core.schema.check(conf.header_schema, headers)
        if not ok then
            core.log.error("req schema validation failed", err)
            return conf.rejected_code, conf.rejected_msg or err
        end
    end

    if conf.body_schema then
        local req_body
        local body, err = core.request.get_body()
        if not body then
            if err then
                core.log.error("failed to get body: ", err)
            end
            return conf.rejected_code, conf.rejected_msg
        end

        local body_is_json = true
        if headers["content-type"] == "application/x-www-form-urlencoded" then
            -- use 0 to avoid truncated result and keep the behavior as the
            -- same as other platforms
            req_body, err = ngx.decode_args(body, 0)
            body_is_json = false
        else -- JSON as default
            req_body, err = core.json.decode(body)
        end

        if not req_body then
            core.log.error('failed to decode the req body: ', err)
            return conf.rejected_code, conf.rejected_msg or err
        end

        local ok, err = core.schema.check(conf.body_schema, req_body)
        if not ok then
            core.log.error("req schema validation failed: ", err)
            return conf.rejected_code, conf.rejected_msg or err
        end

        if body_is_json then
            -- ensure the JSON we check is the JSON we pass to the upstream,
            -- see https://bishopfox.com/blog/json-interoperability-vulnerabilities
            req_body = core.json.encode(req_body)
            ngx.req.set_body_data(req_body)
        end
    end
end

return _M
