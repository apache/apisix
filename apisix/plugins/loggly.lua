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
local plugin = require("apisix.plugin")
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local log_util = require("apisix.utils.log-util")
local json_encode = require("toolkit.json").encode
local ngx = ngx
local tostring = tostring
local pairs = pairs
local tab_concat = table.concat
local udp = ngx.socket.udp

local plugin_name = "loggly"
local batch_processor_manager = bp_manager_mod.new(plugin_name)


local severity = {
    EMEGR = 0,              --  system is unusable
    ALERT = 1,              --  action must be taken immediately
    CRIT = 2,               --  critical conditions
    ERR = 3,                --  error conditions
    WARNING = 4,            --  warning conditions
    NOTICE = 5,             --  normal but significant condition
    INFO = 6,               --  informational
    DEBUG = 7,              --  debug-level messages
}


local severity_enums = {}
do
    for k, _ in pairs(severity) do
        severity_enums[#severity_enums+1] = k
        severity_enums[#severity_enums+1] = k:lower()
    end
end


local schema = {
    type = "object",
    properties = {
        customer_token = {type = "string"},
        severity = {
            type = "string",
            default = "INFO",
            enum = severity_enums,
            description = "base severity log level",
        },
        include_req_body = {type = "boolean", default = false},
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        tags = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                -- we prevent of having `tag=` prefix
                pattern = "^(?!tag=)[ -~]*",
            },
        },
    },
    required = {"customer_token"}
}


local defaults = {
    host = "logs-01.loggly.com",
    port = 514,
    protocol = "syslog",
    timeout = 5000
}


local metadata_schema = {
    type = "object",
    properties = {
        host = {
            type = "string",
            default = defaults.host
        },
        port = {
            type = "integer",
            default = defaults.port
        },
        protocol = {
            type = "string",
            default = defaults.protocol,
            -- more methods coming soon
            enum = {"syslog"}
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default= defaults.timeout
        },
        log_format = {
            type = "object",
        }
    }
}


local _M = {
    version = 0.1,
    priority = 411,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema
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


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


local function generate_log_message(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    local entry

    if metadata and metadata.value.log_format
       and core.table.nkeys(metadata.value.log_format) > 0
    then
        entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
    else
        entry = log_util.get_full_log(ngx, conf)
    end

    -- generate rfc5424 compliant syslog event
    local json_str = json_encode(entry)

    local timestamp = log_util.get_rfc3339_zulu_timestamp()
    local taglist = {}
    if conf.tags then
        for i = 1, #conf.tags do
            core.table.insert(taglist, "tag=\"" .. conf.tags[i] .. "\"")
        end
    end
    local message = {
        -- facility LOG_USER - random user level message
        "<".. tostring(8 + severity[conf.severity:upper()]) .. ">1",-- <PRIVAL>1
        timestamp,                                                  -- timestamp
        ctx.var.host or "-",                                        -- hostname
        "apisix",                                                   -- appname
        ctx.var.pid,                                                -- proc-id
        "-",                                                        -- msgid
        "[" .. conf.customer_token .. "@41058 " .. tab_concat(taglist, " ") .. "]",
        json_str
    }

    return tab_concat(message, " ")
end


local function send_data_over_udp(message)
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    if not metadata then
        core.log.info("received nil metadata: using metadata defaults: ",
                            core.json.delay_encode(defaults, true))
        metadata = {}
        metadata.value = defaults
    end
    local err_msg
    local res = true
    local sock = udp()
    local host, port = metadata.value.host, metadata.value.port
    sock:settimeout(metadata.value.timeout)

    core.log.info("sending a batch logs to ", host, ":", port)

    local ok, err = sock:setpeername(host, port)

    if not ok then
        core.log.error("failed to send log: ", err)
        return false, "failed to connect to UDP server: host[" .. host
                    .. "] port[" .. tostring(port) .. "] err: " .. err
    end

    ok, err = sock:send(message)
    if not ok then
        res = false
        core.log.error("failed to send log: ", err)
        err_msg = "failed to send data to UDP server: host[" .. host
                  .. "] port[" .. tostring(port) .. "] err:" .. err
    end

    ok, err = sock:close()
    if not ok then
        core.log.error("failed to close the UDP connection, host[",
                        host, "] port[", port, "] ", err)
    end

    return res, err_msg
end


local function handle_log(entries)
    for i = 1, #entries do
        local ok, err = send_data_over_udp(entries[i])
        if not ok then
            return false, err
        end
    end
    return true
end


function _M.log(conf, ctx)
    local log_data = generate_log_message(conf, ctx)
    if not log_data then
        return
    end

    if batch_processor_manager:add_entry(conf, log_data) then
        return
    end

    batch_processor_manager:add_entry_to_new_processor(conf, log_data, ctx, handle_log)
end


return _M
