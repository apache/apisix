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
local errlog = require("ngx.errlog")
local batch_processor = require("apisix.utils.batch-processor")
local plugin = require("apisix.plugin")
local timers = require("apisix.timers")
local http = require("resty.http")
local url = require("net.url")
local plugin_name = "error-log-logger"
local table = core.table
local schema_def = core.schema
local ngx = ngx
local tcp = ngx.socket.tcp
local string = string
local tostring = tostring
local ipairs  = ipairs
local lrucache = core.lrucache.new({
    ttl = 300, count = 32
})


local metadata_schema = {
    type = "object",
    properties = {
        type = {type = "string", default = "TCP", enum = {"TCP", "SKYWALKING"}},
        tcp = {
            type = "object",
            properties = {
                host = schema_def.host_def,
                port = {type = "integer", minimum = 0},
                tls = {type = "boolean", default = false},
                tls_server_name = {type = "string"},
                keepalive = {type = "integer", minimum = 1, default = 30},
            },
	    required = {"host", "port"}
        },
        skywalking = {
            type = "object",
            properties = {
                endpoint_addr = schema_def.uri,
                service_name = {type = "string", default = "APISIX"},
                service_instance_name = {type="string", default = "APISIX Service Instance"},
            },
	    required = {"endpoint_addr"}
        },
        name = {type = "string", default = plugin_name},
        level = {type = "string", default = "WARN", enum = {"STDERR", "EMERG", "ALERT", "CRIT",
                "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"}},
        timeout = {type = "integer", minimum = 1, default = 3},
        batch_max_size = {type = "integer", minimum = 0, default = 1000},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 3},
    },
}


local schema = {
    type = "object",
}


local log_level = {
    STDERR =    ngx.STDERR,
    EMERG  =    ngx.EMERG,
    ALERT  =    ngx.ALERT,
    CRIT   =    ngx.CRIT,
    ERR    =    ngx.ERR,
    ERROR  =    ngx.ERR,
    WARN   =    ngx.WARN,
    NOTICE =    ngx.NOTICE,
    INFO   =    ngx.INFO,
    DEBUG  =    ngx.DEBUG
}


local config = {}
local log_buffer


local _M = {
    version = 0.1,
    priority = 1091,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function send_to_tcp_server(data)
    local sock, soc_err = tcp()

    if not sock then
        return false, "failed to init the socket " .. soc_err
    end

    sock:settimeout(config.timeout * 1000)

    local tcp_config = config.tcp
    local ok, err = sock:connect(tcp_config.host, tcp_config.port)
    if not ok then
        return false, "failed to connect the TCP server: host[" .. tcp_config.host
            .. "] port[" .. tostring(tcp_config.port) .. "] err: " .. err
    end

    if tcp_config.tls then
        ok, err = sock:sslhandshake(false, tcp_config.tls_server_name, false)
        if not ok then
            sock:close()
            return false, "failed to perform TLS handshake to TCP server: host["
                .. tcp_config.host .. "] port[" .. tostring(tcp_config.port) .. "] err: " .. err
        end
    end

    local bytes, err = sock:send(data)
    if not bytes then
        sock:close()
        return false, "failed to send data to TCP server: host[" .. tcp_config.host
            .. "] port[" .. tostring(tcp_config.port) .. "] err: " .. err
    end

    sock:setkeepalive(tcp_config.keepalive * 1000)
    return true
end


local function send_to_skywalking(log_message)
    local err_msg
    local res = true
    local url_decoded = url.parse(config.skywalking.endpoint_addr)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", config.skywalking.endpoint_addr)

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(config.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, false)
        if not ok then
            return nil, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local entries = {}
    for i = 1, #log_message, 2 do
        local content = {
            service = config.skywalking.service_name,
            serviceInstance = config.skywalking.service_instance_name,
            endpoint = "",
            body = {
                text = {
                    text = log_message[i]
                }
           }
        }
        table.insert(entries, content)
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        query = url_decoded.query,
        body = core.json.encode(entries),
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = "application/json",
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


local function update_filter(value)
    local level = log_level[string.upper(value.level)]
    local status, err = errlog.set_filter_level(level)
    if not status then
        return nil, "failed to set filter level by ngx.errlog, the error is :" .. err
    else
        core.log.debug("set the filter_level to ", config.level)
    end

    return value
end


local function send(data)
    if config.type == "TCP" then
	    return send_to_tcp_server(data)
    else
	    return send_to_skywalking(data)
    end
end


local function process()
    local metadata = plugin.plugin_metadata(plugin_name)
    if not (metadata and metadata.value and metadata.modifiedIndex) then
        core.log.info("please set the correct plugin_metadata for ", plugin_name)
        return
    else
        local err
        config, err = lrucache(plugin_name, metadata.modifiedIndex, update_filter, metadata.value)
        if not config then
            core.log.warn("set log filter failed for ", err)
            return
        end

    end

    local entries = {}
    local logs = errlog.get_logs(9)
    while ( logs and #logs>0 ) do
        for i = 1, #logs, 3 do
            table.insert(entries, logs[i + 2])
            table.insert(entries, "\n")
        end
        logs = errlog.get_logs(9)
    end

    if #entries == 0 then
        return
    end

    if log_buffer then
        for _, v in ipairs(entries) do
            log_buffer:push(v)
        end
        return
    end

    local config_bat = {
        name = config.name,
        retry_delay = config.retry_delay,
        batch_max_size = config.batch_max_size,
        max_retry_count = config.max_retry_count,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
    }

    local err
    log_buffer, err = batch_processor:new(send, config_bat)

    if not log_buffer then
        core.log.warn("error when creating the batch processor: ", err)
        return
    end

    for _, v in ipairs(entries) do
        log_buffer:push(v)
    end

end


function _M.init()
    timers.register_timer("plugin#error-log-logger", process)
end


function _M.destroy()
    timers.unregister_timer("plugin#error-log-logger")
end


return _M