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

local ngx  = ngx
local require = require
local type = type
local string = string

return function(plugin_name, version, priority, request_processor, authz_schema, metadata_schema)
    local core = require("apisix.core")
    local http = require("resty.http")
    local url = require("net.url")

    if request_processor and type(request_processor) ~= "function" then
        return "Failed to generate plugin due to invalid header processor type, " ..
                    "expected: function, received: " .. type(request_processor)
    end

    local schema = {
        type = "object",
        properties = {
            function_uri = {type = "string"},
            authorization = authz_schema,
            timeout = {type = "integer", minimum = 100, default = 3000},
            ssl_verify = {type = "boolean", default = true},
            keepalive = {type = "boolean", default = true},
            keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
            keepalive_pool = {type = "integer", minimum = 1, default = 5}
        },
        required = {"function_uri"}
    }

    local _M = {
        version = version,
        priority = priority,
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
            core.log.error("error while reading request body: ", err)
            return 400
        end

        -- forward the url path came through the matched uri
        local url_decoded = url.parse(conf.function_uri)
        local path = url_decoded.path or "/"

        if ctx.curr_req_matched and ctx.curr_req_matched[":ext"] then
            local end_path = ctx.curr_req_matched[":ext"]

            if path:byte(-1) == string.byte("/") or end_path:byte(1) == string.byte("/") then
                path = path .. end_path
            else
                path = path .. "/" .. end_path
            end
        end


        headers["host"] = url_decoded.host
        local params = {
            method = ngx.req.get_method(),
            body = req_body,
            query = uri_args,
            headers = headers,
            path = path,
            keepalive = conf.keepalive,
            ssl_verify = conf.ssl_verify
        }

        -- Keepalive options
        if conf.keepalive then
            params.keepalive_timeout = conf.keepalive_timeout
            params.keepalive_pool = conf.keepalive_pool
        end

        -- modify request info (if required)
        request_processor(conf, ctx, params)

        local httpc = http.new()
        httpc:set_timeout(conf.timeout)

        local res
        res, err = httpc:request_uri(conf.function_uri, params)

        if not res then
            core.log.error("failed to process ", plugin_name, ", err: ", err)
            return 503
        end

        -- According to RFC7540 https://datatracker.ietf.org/doc/html/rfc7540#section-8.1.2.2,
        -- endpoint must not generate any connection specific headers for HTTP/2 requests.
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
end
