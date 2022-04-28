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
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local logger_socket = require("resty.logger.socket")

local batch_processor_manager = bp_manager_mod.new("sys logger")

local lrucache = core.lrucache.new({
    ttl = 300, count = 512, serial_creating = true,
})

local _M = {}

function _M.flush_syslog(logger)
    local ok, err = logger:flush(logger)
    if not ok then
        core.log.error("failed to flush message:", err)
    end

    return ok
end


local function send_syslog_data(conf, log_message, api_ctx)
    local err_msg
    local res = true

    core.log.info("sending a batch logs to ", conf.host, ":", conf.port)

    -- fetch it from lrucache
    local logger, err = core.lrucache.plugin_ctx(
        lrucache, api_ctx, nil, logger_socket.new, logger_socket, {
            host = conf.host,
            port = conf.port,
            flush_limit = conf.flush_limit,
            drop_limit = conf.drop_limit,
            timeout = conf.timeout,
            sock_type = conf.sock_type,
            pool_size = conf.pool_size,
            tls = conf.tls,
        }
    )

    if not logger then
        res = false
        err_msg = "failed when initiating the sys logger processor".. err
    end

    -- reuse the logger object
    local ok, err = logger:log(core.json.encode(log_message))
    if not ok then
        res = false
        err_msg = "failed to log message" .. err
    end

    return res, err_msg
end


-- called in log phase of APISIX
function _M.push_entry(conf, ctx, entry)
    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local cp_ctx = core.table.clone(ctx)
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

        return send_syslog_data(conf, data, cp_ctx)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
