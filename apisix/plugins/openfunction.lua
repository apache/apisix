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

local core              = require("apisix.core")
local http              = require("resty.http")
local ngx_encode_base64 = ngx.encode_base64
local ngx  = ngx

local schema = {
    type = "object",
    properties = {
        function_uri = {type = "string"},
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        service_token = {type = "string"},
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 60000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5}
    },
    required = {"function_uri"}
}


local _M = {
    version = 0.1,
    priority = -1902,
    name = "openfunction",
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    local params = {
        method = ngx.req.get_method(),
        body = core.request.get_body(),
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        headers = core.request.headers(ctx) or {}
    }

    -- setting authorization headers if not already set
    if not params.headers["Authorization"] and conf.service_token then
        params.headers["Authorization"] = "Basic " .. ngx_encode_base64(conf.service_token)
    end

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local endpoint = conf.function_uri
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(endpoint, params)

    if not res then
        core.log.error("failed to process ",_M.name, ", err: ", err)
        return 503
    end

    -- setting response headers
    if res.headers ~= nil then
        core.response.set_header(res.headers)
    end

    return res.status, res.body

end


return _M
