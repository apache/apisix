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

local ngx             = ngx
local core            = require("apisix.core")
local ngx_now         = ngx.now
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")

local DEFAULT_ELASTICSEARCH_SOURCE = "apache-apisix-elasticsearch-logging"

local plugin_name = "elasticsearch-logging"
local batch_processor_manager = bp_manager_mod.new(plugin_name)
local str_format = core.string.format


local schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "object",
            properties = {
                uri = core.schema.uri_def,
                index = { type = "string"},
                type = { type = "string"},
                username = { type = "string"},
                password = { type = "string"},
                timeout = {
                    type = "integer",
                    minimum = 1,
                    default = 10
                },
                ssl_verify = {
                    type = "boolean",
                    default = true
                }
            },
            required = { "uri", "index" }
        },
    },
    required = { "endpoint" },
}


local _M = {
    version = 0.1,
    priority = 413,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_logger_entry(conf)
    local entry = log_util.get_full_log(ngx, conf)
    return core.json.encode({
            create = {
                _index = "services",
                _type = "collector"
            }
        }) .. "\n" ..
        core.json.encode({
            time = ngx_now(),
            host = entry.server.hostname,
            source = DEFAULT_ELASTICSEARCH_SOURCE,
            request_url = entry.request.url,
            request_method = entry.request.method,
            request_headers = entry.request.headers,
            request_query = entry.request.querystring,
            request_size = entry.request.size,
            response_headers = entry.response.headers,
            response_status = entry.response.status,
            response_size = entry.response.size,
            latency = entry.latency,
            upstream = entry.upstream,
        }) .. "\n"
end


local function send_to_elasticsearch(conf, entries)
    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http error: %s", err)
    end

    local uri = conf.endpoint.uri .. (string.sub(conf.endpoint.uri, -1) == "/" and "_bulk" or "/_bulk")
    local body = core.table.concat(entries, "")
    local headers = {["Content-Type"] = "application/json"}
    if conf.endpoint.username and conf.endpoint.password then
        local authorization = "Basic " .. ngx.encode_base64(
            conf.endpoint.username .. ":" .. conf.endpoint.password
        )
        headers["Authorization"] = authorization
    end

    core.log.info("uri: ", uri, ", body: ", body, ", headers: ", core.json.encode(headers))

    httpc:set_timeout(conf.endpoint.timeout * 1000)
    local resp, err = httpc:request_uri(uri, {
        ssl_verify = conf.endpoint.ssl_verify,
        method = "POST",
        headers = headers,
        body = body
    })
    if not resp then
        return false,  str_format("RequestError: %s", err or "")
    end

    if resp.status ~= 200 then
        return false, str_format("response status: %d, response body: %s",
        resp.status, resp.body or "")
    end

    return true
end


function _M.log(conf, ctx)
    local entry = get_logger_entry(conf)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_elasticsearch(conf, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end


return _M
