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
local core = require("apisix.core")
local log_util = require("apisix.utils.log-util")
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local plugin_name = "udp-logger"
local tostring = tostring
local ngx = ngx
local udp = ngx.socket.udp


local batch_processor_manager = bp_manager_mod.new("udp logger")
local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer", minimum = 0},
        timeout = {type = "integer", minimum = 1, default = 3},
        log_format = {type = "object"},
        include_req_body = {type = "boolean", default = false}
    },
    required = {"host", "port"}
}

local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}

local _M = {
    version = 0.1,
    priority = 400,
    name = plugin_name,
    metadata_schema = metadata_schema,
    schema = batch_processor_manager:wrap_schema(schema),
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    return core.schema.check(schema, conf)
end


local function send_udp_data(conf, log_message)
    local err_msg
    local res = true
    local sock = udp()
    sock:settimeout(conf.timeout * 1000)

    core.log.info("sending a batch logs to ", conf.host, ":", conf.port)

    local ok, err = sock:setpeername(conf.host, conf.port)

    if not ok then
        return false, "failed to connect to UDP server: host[" .. conf.host
                    .. "] port[" .. tostring(conf.port) .. "] err: " .. err
    end

    ok, err = sock:send(log_message)
    if not ok then
        res = false
        err_msg = "failed to send data to UDP server: host[" .. conf.host
                  .. "] port[" .. tostring(conf.port) .. "] err:" .. err
    end

    ok, err = sock:close()
    if not ok then
        core.log.error("failed to close the UDP connection, host[",
                        conf.host, "] port[", conf.port, "] ", err)
    end

    return res, err_msg
end


function _M.log(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err
        if batch_max_size == 1 then
            data, err = core.json.encode(entries[1]) -- encode as single {}
        else
            data, err = core.json.encode(entries) -- encode as array [{}]
        end

        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_udp_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end

return _M
