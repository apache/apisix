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
local core    = require("apisix.core")
local http    = require("resty.http")
local ngx     = ngx
local io_open = io.open
local ipairs  = ipairs
local pairs   = pairs

local plugin_name = "batch-requests"

local schema = {
    type = "object",
    additionalProperties = false,
}

local req_schema = {
    type = "object",
    properties = {
        query = {
            description = "pipeline query string",
            type = "object"
        },
        headers = {
            description = "pipeline header",
            type = "object"
        },
        timeout = {
            description = "pipeline timeout(ms)",
            type = "integer",
            default = 30000,
        },
        pipeline = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    version = {
                        description = "HTTP version",
                        type = "number",
                        enum = {1.0, 1.1},
                        default = 1.1,
                    },
                    method = {
                        description = "HTTP method",
                        type = "string",
                        enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                                "OPTIONS", "CONNECT", "TRACE"},
                        default = "GET"
                    },
                    path = {
                        type = "string",
                        minLength = 1,
                    },
                    query = {
                        description = "request header",
                        type = "object",
                    },
                    headers = {
                        description = "request query string",
                        type = "object",
                    },
                    ssl_verify = {
                        type = "boolean",
                        default = false
                    },
                }
            }
        }
    },
    anyOf = {
        {required = {"pipeline"}},
    },
}

local _M = {
    version = 0.1,
    priority = 4010,
    name = plugin_name,
    schema = schema
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end


local function check_input(data)
    local ok, err = core.schema.check(req_schema, data)
    if not ok then
        return 400, {message = "bad request body", err = err}
    end
end


local function set_base_header(data)
    if not data.headers then
        return
    end

    for i,req in ipairs(data.pipeline) do
        if not req.headers then
            req.headers = data.headers
        else
            for k, v in pairs(data.headers) do
                if not req.headers[k] then
                    req.headers[k] = v
                end
            end
        end
    end
end


local function set_base_query(data)
    if not data.query then
        return
    end

    for i,req in ipairs(data.pipeline) do
        if not req.query then
            req.query = data.query
        else
            for k, v in pairs(data.query) do
                if not req.query[k] then
                    req.query[k] = v
                end
            end
        end
    end
end


local function getFile(file_name)
    local f = io_open(file_name, 'r')
    if f then
        return f:read("*all")
    end

    return
end


local function aggregate()
    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()
    if not req_body then
        local file_name = ngx.req.get_body_file()
        if file_name then
            req_body = getFile(file_name)
        end

        if not req_body then
            core.response.exit(400, {message = "no request body, you should give at least one pipeline setting"})
        end
    end

    local data, err = core.json.decode(req_body)
    if not data then
        core.response.exit(400, {message = "invalid request body", req_body = req_body, err = err})
    end

    local code, body = check_input(data)
    if code then
        core.response.exit(code, body)
    end

    local httpc = http.new()
    httpc:set_timeout(data.timeout)
    httpc:connect("127.0.0.1", ngx.var.server_port)
    set_base_header(data)
    set_base_query(data)
    local responses, err = httpc:request_pipeline(data.pipeline)
    if not responses then
        core.response.exit(400, {message = "request failed", err = err})
    end

    local aggregated_resp = {}
    for i,r in ipairs(responses) do
        if not r.status then
            core.table.insert(aggregated_resp, {
                status = 504,
                reason = "upstream timeout"
            })
        end
        local sub_resp = {
            status  = r.status,
            reason  = r.reason,
            headers = r.headers,
        }
        if r.has_body then
            sub_resp.body = r:read_body()
        end
        core.table.insert(aggregated_resp, sub_resp)
    end
    core.response.exit(200, aggregated_resp)
end


function _M.api()
    return {
        {
            methods = {"POST"},
            uri = "/apisix/batch",
            handler = aggregate,
        }
    }
end


return _M
