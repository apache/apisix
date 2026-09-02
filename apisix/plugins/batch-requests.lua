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
local core      = require("apisix.core")
local http      = require("resty.http")
local plugin    = require("apisix.plugin")
local ngx       = ngx
local ipairs    = ipairs
local pairs     = pairs
local tonumber  = tonumber
local str_find  = core.string.find
local str_lower = string.lower


local plugin_name = "batch-requests"

local default_uri = "/apisix/batch-requests"

local attr_schema = {
    type = "object",
    properties = {
        uri = {
            type = "string",
            description = "uri for batch-requests",
            default = default_uri
        }
    },
}

local schema = {
    type = "object",
}

local default_max_body_size = 1024 * 1024 -- 1MiB
local default_max_pipeline_items = 1000
local default_max_response_body_size = 1024 * 1024 -- 1MiB
local default_max_response_body_size_total = 10 * 1024 * 1024 -- 10MiB
local response_body_chunk_size = 8192
local metadata_schema = {
    type = "object",
    properties = {
        max_body_size = {
            description = "max pipeline body size in bytes",
            type = "integer",
            exclusiveMinimum = 0,
            default = default_max_body_size,
        },
        max_pipeline_items = {
            description = "max number of requests allowed in the pipeline",
            type = "integer",
            exclusiveMinimum = 0,
            default = default_max_pipeline_items,
        },
        max_response_body_size = {
            description = "max response body size in bytes for each pipeline request",
            type = "integer",
            exclusiveMinimum = 0,
            default = default_max_response_body_size,
        },
        max_response_body_size_total = {
            description = "max total response body size in bytes for a pipeline",
            type = "integer",
            exclusiveMinimum = 0,
            default = default_max_response_body_size_total,
        },
    },
}

local method_schema = core.table.clone(core.schema.method_schema)
method_schema.default = "GET"

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
            minimum = 1,
            default = 30000,
        },
        pipeline = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                additionalProperties = false,
                properties = {
                    version = {
                        description = "HTTP version",
                        type = "number",
                        enum = {1.0, 1.1},
                        default = 1.1,
                    },
                    method = method_schema,
                    path = {
                        type = "string",
                        minLength = 1,
                    },
                    query = {
                        description = "request query string",
                        type = "object",
                    },
                    headers = {
                        description = "request headers",
                        type = "object",
                    },
                    body = {
                        description = "request body",
                        type = "string",
                    },
                    ssl_verify = {
                        type = "boolean",
                        default = false
                    },
                },
                required = {"path"},
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
    schema = schema,
    metadata_schema = metadata_schema,
    attr_schema = attr_schema,
    scope = "global",
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function check_input(data)
    local ok, err = core.schema.check(req_schema, data)
    if not ok then
        return 400, {error_msg = "bad request body: " .. err}
    end
end

local function lowercase_key_or_init(obj)
    if not obj then
        return {}
    end

    local lowercase_key_obj = {}
    for k, v in pairs(obj) do
        lowercase_key_obj[str_lower(k)] = v
    end

    return lowercase_key_obj
end

local function ensure_header_lowercase(data)
    data.headers = lowercase_key_or_init(data.headers)

    for i,req in ipairs(data.pipeline) do
        req.headers = lowercase_key_or_init(req.headers)
    end
end


local function set_common_header(data)
    local local_conf = core.config.local_conf()
    local real_ip_hdr = core.table.try_read_attr(local_conf, "nginx_config", "http",
                                                 "real_ip_header")
    -- we don't need to handle '_' to '-' as Nginx won't treat 'X_REAL_IP' as 'X-Real-IP'
    real_ip_hdr = str_lower(real_ip_hdr)

    local outer_headers = core.request.headers(nil)
    for i,req in ipairs(data.pipeline) do
        for k, v in pairs(data.headers) do
            if not req.headers[k] then
                req.headers[k] = v
            end
        end

        if outer_headers then
            for k, v in pairs(outer_headers) do
                local is_content_header = str_find(k, "content-") == 1
                -- skip header start with "content-"
                if not req.headers[k] and not is_content_header then
                    req.headers[k] = v
                end
            end
        end

        req.headers[real_ip_hdr] = core.request.get_remote_client_ip()
    end
end


local function set_common_query(data)
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


local function close_http_client(httpc)
    local ok, err = httpc:close()
    if not ok then
        core.log.warn("failed to close batch request connection: ", err)
    end
end


local function read_response_body(httpc, resp, max_response_body_size,
                                  response_body_size_total,
                                  max_response_body_size_total)
    local content_length = tonumber(resp.headers["Content-Length"])
    if content_length then
        if content_length > max_response_body_size then
            close_http_client(httpc)
            return nil, nil, "max_response_body_size"
        end

        if response_body_size_total + content_length > max_response_body_size_total then
            close_http_client(httpc)
            return nil, nil, "max_response_body_size_total"
        end
    end

    local chunks = {}
    local response_body_size = 0
    while true do
        local chunk, err = resp.body_reader(response_body_chunk_size)
        if err then
            close_http_client(httpc)
            return nil, err
        end
        if not chunk then
            break
        end

        response_body_size = response_body_size + #chunk
        if response_body_size > max_response_body_size then
            close_http_client(httpc)
            return nil, nil, "max_response_body_size"
        end

        if response_body_size_total + response_body_size > max_response_body_size_total then
            close_http_client(httpc)
            return nil, nil, "max_response_body_size_total"
        end

        core.table.insert(chunks, chunk)
    end

    return core.table.concat(chunks), nil, nil, response_body_size
end


local function batch_requests(ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    local max_body_size
    local max_pipeline_items
    local max_response_body_size
    local max_response_body_size_total
    if metadata then
        max_body_size = metadata.value.max_body_size
        max_pipeline_items = metadata.value.max_pipeline_items or default_max_pipeline_items
        max_response_body_size = metadata.value.max_response_body_size or
                                 default_max_response_body_size
        max_response_body_size_total = metadata.value.max_response_body_size_total or
                                       default_max_response_body_size_total
    else
        max_body_size = default_max_body_size
        max_pipeline_items = default_max_pipeline_items
        max_response_body_size = default_max_response_body_size
        max_response_body_size_total = default_max_response_body_size_total
    end

    local req_body, err = core.request.get_body(max_body_size, ctx)
    if err then
        -- Nginx doesn't support 417: https://trac.nginx.org/nginx/ticket/2062
        -- So always return 413 instead
        return 413, { error_msg = err }
    end
    if not req_body then
        return 400, {
            error_msg = "no request body, you should give at least one pipeline setting"
        }
    end

    local data, err = core.json.decode(req_body)
    if not data then
        return 400, {
            error_msg = "invalid request body: " .. req_body .. ", err: " .. err
        }
    end

    local code, body = check_input(data)
    if code then
        return code, body
    end

    if #data.pipeline > max_pipeline_items then
        return 400, {
            error_msg = "too many pipeline requests, " .. #data.pipeline ..
                        " exceeds the maximum of " .. max_pipeline_items
        }
    end

    local httpc = http.new()
    httpc:set_timeout(data.timeout)
    local ok, err = httpc:connect("127.0.0.1", ngx.var.server_port)
    if not ok then
        return 500, {error_msg = "connect to apisix failed: " .. err}
    end

    ensure_header_lowercase(data)
    set_common_header(data)
    set_common_query(data)

    local responses, err = httpc:request_pipeline(data.pipeline)
    if not responses then
        return 400, {error_msg = "request failed: " .. err}
    end

    local aggregated_resp = {}
    local response_body_size_total = 0
    for i, resp in ipairs(responses) do
        if not resp.status then
            core.table.insert(aggregated_resp, {
                status = 504,
                reason = "upstream timeout"
            })
            goto CONTINUE
        end
        local sub_resp = {
            status  = resp.status,
            reason  = resp.reason,
            headers = resp.headers,
        }
        if resp.has_body then
            local err, limit_name, response_body_size
            sub_resp.body, err, limit_name, response_body_size =
                read_response_body(httpc, resp, max_response_body_size,
                                   response_body_size_total,
                                   max_response_body_size_total)
            if limit_name then
                return 502, {
                    error_msg = "response body of pipeline request " .. i ..
                                " exceeds " .. limit_name
                }
            end
            if err then
                sub_resp.read_body_err = err
                core.log.error("read pipeline response body failed: ", err)
            else
                response_body_size_total = response_body_size_total + response_body_size
                resp:read_trailers()
            end
        end
        core.table.insert(aggregated_resp, sub_resp)
        ::CONTINUE::
    end
    return 200, aggregated_resp
end


function _M.api()
    local uri = default_uri
    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        uri = attr.uri or default_uri
    end
    return {
        {
            methods = {"POST"},
            uri = uri,
            handler = batch_requests,
        }
    }
end


return _M
