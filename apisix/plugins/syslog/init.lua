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
local plugin = require("apisix.plugin")
local rfc5424 = require("apisix.utils.rfc5424")
local ipairs = ipairs
local table_insert = core.table.insert
local table_concat = core.table.concat

local plugin_name = "sys logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

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
    local ok, err = logger:log(log_message)

    if not ok then
        res = false
        err_msg = "failed to log message" .. err
    end

    return res, err_msg
end


-- called in log phase of APISIX
function _M.push_entry(conf, ctx, entry)
    local json_str, err = core.json.encode(entry)
    if not json_str then
        core.log.error('error occurred while encoding the data: ', err)
        return
    end

    local rfc5424_data = rfc5424.encode("SYSLOG", "INFO", ctx.var.host,
                                "apisix", ctx.var.pid, json_str)
    core.log.info("collect_data:" .. rfc5424_data)
    local metadata = plugin.plugin_metadata(plugin_name)
    local max_pending_entries = metadata and metadata.value and
                                metadata.value.max_pending_entries or nil
    if batch_processor_manager:add_entry(conf, rfc5424_data, max_pending_entries) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local cp_ctx = core.table.clone(ctx)
    local func = function(entries)
        local items = {}
        for _, e in ipairs(entries) do
            table_insert(items, e)
            core.log.debug("buffered logs:", e)
        end

        return send_syslog_data(conf, table_concat(items), cp_ctx)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, rfc5424_data,
                                                       ctx, func, max_pending_entries)
end


return _M
