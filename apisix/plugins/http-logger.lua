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

local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local log_util        = require("apisix.utils.log-util")
local core            = require("apisix.core")
local http            = require("resty.http")
local url             = require("net.url")

local tostring = tostring
local ipairs   = ipairs

local plugin_name = "http-logger"
local batch_processor_manager = bp_manager_mod.new("http logger")

local schema = {
    type = "object",
    properties = {
        uri = core.schema.uri_def,
        auth_header = {type = "string"},
        timeout = {type = "integer", minimum = 1, default = 3},
        log_format = {type = "object"},
        include_req_body = {type = "boolean", default = false},
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        concat_method = {type = "string", default = "json",
                         enum = {"json", "new_line"}},
        ssl_verify = {type = "boolean", default = false},
    },
    required = {"uri"}
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 410,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end
    return log_util.check_log_schema(conf)
end


local function send_http_data(conf, log_message)
    local err_msg
    local res = true
    local url_decoded = url.parse(conf.uri)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", conf.uri)

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, conf.ssl_verify)
        if not ok then
            return false, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local content_type
    if conf.concat_method == "json" then
        content_type = "application/json"
    else
        content_type = "text/plain"
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        query = url_decoded.query,
        body = log_message,
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = content_type,
            ["Authorization"] = conf.auth_header
        }
    })

    if not httpc_res then
        return false, "error while sending data to [" .. host .. "] port["
            .. tostring(port) .. "] " .. httpc_err
    end

    -- some error occurred in the server
    if httpc_res.status >= 400 then
        res =  false
        err_msg = "server returned status code[" .. httpc_res.status .. "] host["
            .. host .. "] port[" .. tostring(port) .. "] "
            .. "body[" .. httpc_res:read_body() .. "]"
    end

    return res, err_msg
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if not entry.route_id then
        entry.route_id = "no-matched"
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err

        if conf.concat_method == "json" then
            if batch_max_size == 1 then
                data, err = core.json.encode(entries[1]) -- encode as single {}
            else
                data, err = core.json.encode(entries) -- encode as array [{}]
            end

        elseif conf.concat_method == "new_line" then
            if batch_max_size == 1 then
                data, err = core.json.encode(entries[1]) -- encode as single {}
            else
                local t = core.table.new(#entries, 0)
                for i, entry in ipairs(entries) do
                    t[i], err = core.json.encode(entry)
                    if err then
                        core.log.warn("failed to encode http log: ", err, ", log data: ", entry)
                        break
                    end
                end
                data = core.table.concat(t, "\n") -- encode as multiple string
            end

        else
            -- defensive programming check
            err = "unknown concat_method " .. (conf.concat_method or "nil")
        end

        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_http_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
