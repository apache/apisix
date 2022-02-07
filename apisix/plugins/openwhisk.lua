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
local tostring          = tostring

local name_pattern = [[\A([\w]|[\w][\w@ .-]*[\w@.-]+)\z]]

local schema = {
    type = "object",
    properties = {
        api_host = {type = "string"},
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        service_token = {type = "string"},
        namespace = {type = "string", maxLength = 256, pattern = name_pattern},
        package = {type = "string", maxLength = 256, pattern = name_pattern},
        action = {type = "string", maxLength = 256, pattern = name_pattern},
        result = {
            type = "boolean",
            default = true,
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5}
    },
    required = {"api_host", "service_token", "namespace", "action"}
}


local _M = {
    version = 0.1,
    priority = -1901,
    name = "openwhisk",
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
        method = "POST",
        body = core.request.get_body(),
        query = {
            blocking = "true",
            result = tostring(conf.result),
            timeout = conf.timeout
        },
        headers = {
            ["Authorization"] = "Basic " .. ngx_encode_base64(conf.service_token),
            ["Content-Type"] = "application/json",
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    -- OpenWhisk action endpoint
    local package = conf.package and conf.package .. "/" or ""
    local endpoint = conf.api_host .. "/api/v1/namespaces/" .. conf.namespace ..
        "/actions/" .. package .. conf.action

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(endpoint, params)

    if not res then
        core.log.error("failed to process openwhisk action, err: ", err)
        return 503
    end

    -- check if res.body is nil
    if res.body == nil then
        return res.status, res.body
    end

    -- parse OpenWhisk JSON response
    -- OpenWhisk supports two types of responses, the user can return only
    -- the response body, or set the status code and header.
    local result, err = core.json.decode(res.body)

    if not result then
        core.log.error("failed to parse openwhisk response data: ", err)
        return 503
    end

    -- setting response headers
    if result.headers ~= nil then
        core.response.set_header(result.headers)
    end

    local code = result.statusCode or res.status
    local body = result.body or res.body
    return code, body

end


return _M
