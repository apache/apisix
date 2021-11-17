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
local plugin = require("apisix.plugin")
local ngx  = ngx
local plugin_name = "azure-functions"

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

local metadata_schema = {
    type = "object",
    properties = {
        master_apikey = {type = "string", default = ""},
        master_clientid = {type = "string", default = ""}
    }
}

local _M = {
    version = 0.1,
    priority = -1900,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
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
            headers["x-functions-key"] = conf.authorization.apikey
            headers["x-functions-clientid"] = conf.authorization.clientid
        else
            -- If neither api keys are set with the client request nor inside the plugin attributes
            -- plugin will fallback to the master key (if any) present inside the metadata.
            local metadata = plugin.plugin_metadata(plugin_name)
            if metadata then
                headers["x-functions-key"] = metadata.value.master_apikey
                headers["x-functions-clientid"] = metadata.value.master_clientid
            end
        end
    end

    headers["Host"],  headers["host"] = nil, nil
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

    -- According to RFC7540 https://datatracker.ietf.org/doc/html/rfc7540#section-8.1.2.2, endpoint
    -- must not generate any connection specific headers for HTTP/2 requests.
    local response_headers = res.headers
    if ngx.var.http2 then
        response_headers["Connection"] = nil
        response_headers["Keep-Alive"] = nil
        response_headers["Proxy-Connection"] = nil
        response_headers["Upgrade"] = nil
        response_headers["Transfer-Encoding"] = nil
    end

    -- setting response headers
    core.response.set_header(response_headers)

    return res.status, res.body
end

return _M
