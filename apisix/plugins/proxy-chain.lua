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

local core = require("apisix.core")        -- Core APISIX utilities
local http = require("resty.http")         -- HTTP client for making service calls
local cjson = require("cjson")             -- JSON encoding/decoding library

local plugin_name = "proxy-chain"

-- Schema definition for plugin configuration
local schema = {
    type = "object",
    properties = {
        services = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    uri = { type = "string", minLength = 1 },          -- URI of the service to call
                    method = { type = "string", enum = {"GET", "POST", "PUT", "DELETE"}, default = "POST" }  -- HTTP method
                },
                required = {"uri"}  -- URI is mandatory
            },
            minItems = 1  -- At least one service must be specified
        },
        token_header = { type = "string" }  -- Optional header name for passing a token
    },
    required = {"services"}  -- Services array is mandatory
}

-- Plugin metadata
local _M = {
    version = 0.1,                    -- Plugin version
    priority = 1000,                  -- Execution priority (higher runs earlier)
    name = plugin_name,               -- Plugin name
    schema = schema,                  -- Configuration schema
    description = "A plugin to chain multiple service requests and merge their responses."
}

-- Validate the plugin configuration against the schema
function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- Access phase: Chain service calls and merge responses
function _M.access(conf, ctx)
    -- Read the incoming request body
    ngx.req.read_body()
    local original_body = ngx.req.get_body_data()
    local original_data = {}

    -- Log the original request body
    core.log.info("Original body: ", original_body or "nil")
    if original_body and original_body ~= "" then
        local success, decoded = pcall(cjson.decode, original_body)
        if success then
            original_data = decoded  -- Parse JSON body if valid
        else
            core.log.warn("Invalid JSON in original body: ", original_body)
        end
    end

    -- Merge URI arguments into the original data
    local uri_args = ngx.req.get_uri_args()
    for k, v in pairs(uri_args) do
        original_data[k] = v
    end

    -- Extract authentication token from headers
    local headers = ngx.req.get_headers()
    local auth_header
    if conf.token_header then
        -- Check custom token header (case-insensitive)
        local token = headers[conf.token_header] or headers[conf.token_header:lower()] or ""
        if token == "" then
            core.log.info("No token found in header: ", conf.token_header, ", falling back to Authorization")
            token = headers["Authorization"] or headers["authorization"] or ""
            if token ~= "" then
                token = token:gsub("^Bearer%s+", "")  -- Remove "Bearer " prefix
            end
        end
        if token ~= "" then
            core.log.info("Token extracted from ", conf.token_header, ": ", token)
            auth_header = "Bearer " .. token
        else
            core.log.info("No token provided in ", conf.token_header, " or Authorization, proceeding without auth")
        end
    else
        -- Fallback to Authorization header if no token_header is specified
        local token = headers["Authorization"] or headers["authorization"] or ""
        if token ~= "" then
            token = token:gsub("^Bearer%s+", "")
            core.log.info("Token extracted from Authorization: ", token)
            auth_header = "Bearer " .. token
        else
            core.log.info("No token_header specified and no Authorization provided, proceeding without auth")
        end
    end

    -- Initialize merged data with original request data
    local merged_data = core.table.deepcopy(original_data)

    -- Iterate through each service in the chain
    for i, service in ipairs(conf.services) do
        local httpc = http.new()
        local service_headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "*/*"
        }
        if auth_header then
            service_headers["Authorization"] = auth_header  -- Add auth token to headers
        end

        -- Make the HTTP request to the service
        local res, err = httpc:request_uri(service.uri, {
            method = service.method,
            body = cjson.encode(merged_data),
            headers = service_headers
        })

        if not res then
            core.log.error("Failed to call service ", service.uri, ": ", err)
            return 500, { error = "Failed to call service: " .. service.uri }
        end

        if res.status ~= 200 then
            core.log.error("Service ", service.uri, " returned non-200 status: ", res.status, " body: ", res.body or "nil")
            return res.status, { error = "Service error", body = res.body }
        end

        core.log.info("Response from ", service.uri, ": ", res.body or "nil")

        -- Parse the service response
        local service_data = {}
        if res.body and res.body ~= "" then
            local success, decoded = pcall(cjson.decode, res.body)
            if success then
                service_data = decoded
            else
                core.log.error("Invalid JSON in response from ", service.uri, ": ", res.body)
                return 500, { error = "Invalid JSON in response from " .. service.uri }
            end
        end

        -- Merge service response into the cumulative data
        for k, v in pairs(service_data) do
            merged_data[k] = v
        end
    end

    -- Prepare the final body to send to the upstream
    local new_body = cjson.encode(merged_data)
    core.log.info("Merged data sent to upstream: ", new_body)

    -- Store the merged response in context and update the request
    ctx.proxy_chain_response = merged_data
    ngx.req.set_body_data(new_body)
    if auth_header then
        ngx.req.set_header("Authorization", auth_header)  -- Pass token to upstream
    end
end

return _M
