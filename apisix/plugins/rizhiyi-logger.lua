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
local plugin = require("apisix.plugin")

local tcp = ngx.socket.tcp

local plugin_name = "rizhiyi-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

---calc pri---
local Facility = {
      kern = 0,    user = 1,     mail = 2,  daemon = 3,
      auth = 4,  syslog = 5,      lrp = 6,    news = 7,
      uucp = 8,    cron = 9, authpriv = 10,    ftp = 11,
    local0 = 16, local1 = 17,  local2 = 18, local3 = 19,
    local4 = 20, local5 = 21,  local6 = 22, local7 = 23
}

local Severity = {
     emerg = 0,  alert = 1, crit = 2,   err = 3,
    warning = 4, notice = 5, info = 6, debug = 7
}
---

local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        token = {type = "string"},
        appname = {type = "string"},
        tag = {type = "string"},
        facility = {type = "string", default = "syslog"},
        severity = {type = "string", default = "info"},
        timeout = {type = "integer", minimum = 1, default = 5000}
    },
    required = {"host", "port", "token", "appname", "tag"}
}

local _M = {
    version = 0.1,
    priority = 396,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema)
}

function _M.check_schema(conf)
   return core.schema.check(schema, conf)
end

local function send_tcp_data(route_conf, log_message)
    local err_msg
    local res = true
    local sock, soc_err = tcp()
    local can_close

    if not sock then
        return false, "Failed to init the socket: " .. soc_err
    end

    sock:settimeout(route_conf.timeout)
    local ok, err = sock:connect(route_conf.host, route_conf.port)
    if not ok then
        return false, "Failed to connect to Collector: " .. route_conf.host .. ":" .. tostring(route_conf.port) .. " err: " .. err
    end

    ok, err = sock:send(log_message)
    if not ok then
        res = false
        can_close = true
        err_msg = "Failed to send data to Collector: " .. route_conf.host .. ":" .. tostring(route_conf.port) .. " err: " .. err
    else
        ok, err = sock:setkeepalive(120 * 1000, 20)
        if not ok then
            can_close = true
            core.log.warn("Failed to set socket keepalive: ", route_conf.host, ":", tostring(route_conf.port), " err: ", err)
        end
    end

    if  can_close then
        ok, err = sock:close()
        if not ok then
            core.log.warn("Failed to close the TCP connection: ", route_conf.host, ":", route_conf.port, " err: ", err)
        end
    end

    return res, err_msg
end

function _M.log(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    local entry

    if metadata and metadata.value.log_format
       and core.table.nkeys(metadata.value.log_format) > 0
    then
        entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
    else
        entry = log_util.get_full_log(ngx, conf)
    end

    local json_str, err = core.json.encode(entry)
    if not json_str then
        core.log.error('Error occurred while encoding the data: ', err)
        return
    end

    local pri = (Facility[conf.facility] * 8 + Severity[conf.severity])
    local t = log_util.get_rfc3339_zulu_timestamp()
    local hostname = ctx.var.host
    local appname = conf.appname
    local token = conf.token
    local tag = conf.tag
    local msg = json_str

    local log_message = "<" .. pri .. ">1 " .. t .. " " .. hostname .. " " .. appname
                        .. " - - [" .. token .. "@32473 tag=\"" .. tag .. "\"] " .. msg .. "\n"

    local entries = {
        route_conf = conf,
        log_message = log_message
    }

    if batch_processor_manager:add_entry(conf, entries) then
        return
    end

    local func = function(entries)
        return send_tcp_data(entries[1].route_conf, entries[1].log_message)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entries, ctx, func)
end

return _M
