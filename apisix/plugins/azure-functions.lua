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

local core = require("apisix.core")
local http = require("resty.http")
local ngx  = ngx
local getenv = os.getenv
local plugin_name = "azure-functions"

local env_key = {
    API = "AZURE_FUNCTIONS_APIKEY",
    CLIENT_ID = "AZURE_FUNCTIONS_CLIENTID"
}

local schema = {
    type = "object",
    properties = {
        function_uri = {type = "string"},
        authorization = {
            type = "object",
            properties = {
                apikey = {type = "string"},
                clientid = {type = "string"}
            }
        },
        timeout = {type = "integer", minimum = 1000, default = 3000},
        ssl_verify = {type = "boolean", default = true},
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5}
    },
    required = {"function_uri"}
}

local _M = {
    version = 0.1,
    priority = 505,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    local uri_args = core.request.get_uri_args(ctx)
    local headers = core.request.headers(ctx) or {}
    local req_body, err = core.request.get_body()

    if err then
        core.log.error("error while reading request body: " .. err)
        return 400
    end

    -- set authorization headers if not already set by the client
    -- we are following not to overwrite the authz keys
    if not headers["x-functions-key"] and
            not headers["x-functions-clientid"] then
        if conf.authorization then
            headers["x-functions-key"] = conf.authorization.apikey or ""
            headers["x-functions-clientid"] = conf.authorization.clientid or ""
        else
            headers["x-functions-key"] = getenv(env_key.API)
            headers["x-functions-clientid"] = getenv(env_key.CLIENT_ID)
        end
    end

    local params = {
        method = ngx.req.get_method(),
        body = req_body,
        query = uri_args,
        headers = headers,
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify
    }

    -- Keepalive options
    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(conf.function_uri, params)

    if not res or err then
        core.log.error("failed to process azure function, err: " .. err)
        return 503
    end

    -- setting response headers
    core.response.set_header(res.headers)

    return res.status, res.body
end

return _M
