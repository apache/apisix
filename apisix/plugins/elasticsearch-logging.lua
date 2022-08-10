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

local core            = require("apisix.core")
local ngx             = ngx
local ngx_now         = ngx.now
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")

local DEFAULT_ELASTICSEARCH_SOURCE = "apache-apisix-elasticsearch-logging"

local plugin_name = "elasticsearch-logging"
local batch_processor_manager = bp_manager_mod.new(plugin_name)


local schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "object",
            properties = {
                uri = core.schema.uri_def,
                timeout = {
                    type = "integer",
                    minimum = 1,
                    default = 10
                }
            },
            required = { "uri" }
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
    local http_new, err = http.new()
    if not http_new then
        return false, string.format("create http error: %s", err)
    end

    local m, err = http:parse_uri(conf.endpoint.uri)
    if not m then
        return false, "endpoint uri is invalid"
    end

    http_new:set_timeout(conf.endpoint.timeout * 1000)

    local ok, err = http_new:connect({
        scheme = m[1],
        host = m[2],
        port = m[3],
        ssl_verify = m[1] == "https" and false or conf.endpoint.ssl_verify,
    })

    if not ok then
        return false, string.format("failed to connect elasticsearch error: %, \
        host: %s, port: %d", err, m[2], m[3])
    end

    local body = table.concat(entries, "")
    core.log.error("conf.endpoint.uri: ", conf.endpoint.uri, ", body: ", body)
    core.log.info("conf.endpoint.uri: ", conf.endpoint.uri, ", body: ", body)

    local response, err = http_new:request({
        path = m[4],
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = body
    })
    if not response then
        return false,  string.format("RequestError: %s", err or "")
    end

    if response.status ~= 200 then
        return false, string.format("response status: %d, response body: %s",
            response.status, response:read_body() or "")
    end

    local resp_body, err = response:read_body()
    if not resp_body then
        return false, string.format("ReadBodyError: ", err)
    end

    core.log.error("resp_body: ", resp_body)
    core.log.info("resp_body: ", resp_body)

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
