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

local core = require("apisix.core")
local plugin = require("apisix.plugin")
local batch_processor = require("apisix.utils.batch-processor")
local fetch_log = require("apisix.utils.log-util").get_full_log
local service_fetch = require("apisix.http.service").get
local ngx = ngx
local udp = ngx.socket.udp
local format = string.format
local concat = table.concat
local buffers = {}
local ipairs = ipairs
local tostring = tostring
local stale_timer_running = false
local timer_at = ngx.timer.at

local plugin_name = "datadog"
local defaults = {
    host = "127.0.0.1",
    port = 8125,
    namespace = "apisix",
    constant_tags = {"source:apisix"}
}

local schema = {
    type = "object",
    properties = {
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
        batch_max_size = {type = "integer", minimum = 1, default = 5000},
        max_retry_count = {type = "integer", minimum = 1, default = 1},
        prefer_name = {type = "boolean", default = true}
    }
}

local metadata_schema = {
    type = "object",
    properties = {
        host = {type = "string", default= defaults.host},
        port = {type = "integer", minimum = 0, default = defaults.port},
        namespace = {type = "string", default = defaults.namespace},
        constant_tags = {
            type = "array",
            items = {type = "string"},
            default = defaults.constant_tags
        }
    },
}

local _M = {
    version = 0.1,
    priority = 495,
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

local function generate_tag(entry, const_tags)
    local tags
    if const_tags and #const_tags > 0 then
        tags = core.table.clone(const_tags)
    else
        tags = {}
    end

    if entry.route_id and entry.route_id ~= "" then
        core.table.insert(tags, "route_name:" .. entry.route_id)
    end

    if entry.service_id and entry.service_id ~= "" then
        core.table.insert(tags, "service_name:" .. entry.service_id)
    end

    if entry.consumer and entry.consumer ~= "" then
        core.table.insert(tags, "consumer:" .. entry.consumer)
    end
    if entry.balancer_ip ~= "" then
        core.table.insert(tags, "balancer_ip:" .. entry.balancer_ip)
    end
    if entry.response.status then
        core.table.insert(tags, "response_status:" .. entry.response.status)
    end
    if entry.scheme ~= "" then
        core.table.insert(tags, "scheme:" .. entry.scheme)
    end

    if #tags > 0 then
        return "|#" .. concat(tags, ',')
    end

    return ""
end

-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in ipairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, conf: ",
                          core.json.delay_encode(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end

function _M.log(conf, ctx)

    if not stale_timer_running then
        -- run the timer every 30 mins if any log is present
        timer_at(1800, remove_stale_objects)
        stale_timer_running = true
    end

    local entry = fetch_log(ngx, {})
    entry.upstream_latency = ctx.var.upstream_response_time * 1000
    entry.balancer_ip = ctx.balancer_ip or ""
    entry.scheme = ctx.upstream_scheme or ""

    -- if prefer_name is set, fetch the service/route name. If the name is nil, fall back to id.
    if conf.prefer_name then
        if entry.service_id and entry.service_id ~= "" then
            local svc = service_fetch(entry.service_id)

            if svc and svc.value.name ~= "" then
                entry.service_id =  svc.value.name
            end
        end

        if ctx.route_name and ctx.route_name ~= "" then
            entry.route_id = ctx.route_name
        end
    end

    local log_buffer = buffers[conf]
    if log_buffer then
        log_buffer:push(entry)
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        -- Fetching metadata details
        local metadata = plugin.plugin_metadata(plugin_name)
        if not metadata then
            core.log.info("received nil metadata: using metadata defaults: ",
                                core.json.delay_encode(defaults, true))
            metadata = {}
            metadata.value = defaults
        end

        -- Creating a udp socket
        local sock = udp()
        local host, port = metadata.value.host, metadata.value.port
        core.log.info("sending batch metrics to dogstatsd: ", host, ":", port)

        local ok, err = sock:setpeername(host, port)

        if not ok then
            return false, "failed to connect to UDP server: host[" .. host
                        .. "] port[" .. tostring(port) .. "] err: " .. err
        end

        -- Generate prefix & suffix according dogstatsd udp data format.
        local prefix = metadata.value.namespace
        if prefix ~= "" then
            prefix = prefix .. "."
        end

        core.log.info("datadog batch_entry: ", core.json.delay_encode(entries, true))
        for _, entry in ipairs(entries) do
            local suffix = generate_tag(entry, metadata.value.constant_tags)

            -- request counter
            local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                            "request.counter", 1, "c", suffix))
            if not ok then
                core.log.error("failed to report request count to dogstatsd server: host[" .. host
                        .. "] port[" .. tostring(port) .. "] err: " .. err)
            end


            -- request latency histogram
            local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                        "request.latency", entry.latency, "h", suffix))
            if not ok then
                core.log.error("failed to report request latency to dogstatsd server: host["
                        .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
            end

            -- upstream latency
            local apisix_latency = entry.latency
            if entry.upstream_latency then
                local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                        "upstream.latency", entry.upstream_latency, "h", suffix))
                if not ok then
                    core.log.error("failed to report upstream latency to dogstatsd server: host["
                                .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
                end
                apisix_latency =  apisix_latency - entry.upstream_latency
                if apisix_latency < 0 then
                    apisix_latency = 0
                end
            end

            -- apisix_latency
            local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                            "apisix.latency", apisix_latency, "h", suffix))
            if not ok then
                core.log.error("failed to report apisix latency to dogstatsd server: host[" .. host
                        .. "] port[" .. tostring(port) .. "] err: " .. err)
            end

            -- request body size timer
            local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                            "ingress.size", entry.request.size, "ms", suffix))
            if not ok then
                core.log.error("failed to report req body size to dogstatsd server: host[" .. host
                        .. "] port[" .. tostring(port) .. "] err: " .. err)
            end

            -- response body size timer
            local ok, err = sock:send(format("%s:%s|%s%s", prefix ..
                                            "egress.size", entry.response.size, "ms", suffix))
            if not ok then
                core.log.error("failed to report response body size to dogstatsd server: host["
                        .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
            end
        end

        -- Releasing the UDP socket desciptor
        ok, err = sock:close()
        if not ok then
            core.log.error("failed to close the UDP connection, host[",
                            host, "] port[", port, "] ", err)
        end

        -- Returning at the end and ensuring the resource has been released.
        return true
    end
    local config = {
        name = plugin_name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    local err
    log_buffer, err = batch_processor:new(func, config)

    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end

    buffers[conf] = log_buffer
    log_buffer:push(entry)
end

return _M
