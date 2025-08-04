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
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local fetch_log = require("apisix.utils.log-util").get_full_log
local service_fetch = require("apisix.http.service").get
local ngx = ngx
local udp = ngx.socket.udp
local format = string.format
local concat = table.concat
local tostring = tostring
local ipairs = ipairs
local floor = math.floor
local unpack = unpack

local plugin_name = "datadog"
local defaults = {
    host = "127.0.0.1",
    port = 8125,
    namespace = "apisix",
    constant_tags = {"source:apisix"}
}

local batch_processor_manager = bp_manager_mod.new(plugin_name)

-- Shared schema for individual tag strings.
local tag_schema = {
    type = "string",
    -- Tags must be between 1 and 200 characters.
    minLength = 1,
    maxLength = 200,
    -- Tags must follow the Datadog tag format:
    --   - `^[\p{L}]`: Must start with any kind of Unicode letter.
    --   - `[\p{L}\p{N}_.:/-]*`: Followed by Unicode letters (\p{L}), numbers (\p{N}),
    --     or the allowed special characters (underscore, hyphen, colon,
    --     period, and slash).
    --   - `(?<!:)$`: Must not end with a colon.
    pattern = [[^[\p{L}][\p{L}\p{N}_.:/-]*(?<!:)$]]
}

local schema = {
    type = "object",
    properties = {
        prefer_name = {type = "boolean", default = true},
        include_path = {type = "boolean", default = false},
        include_method = {type = "boolean", default = false},
        constant_tags = {
            type = "array",
            items = tag_schema,
            default = {}
        }
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
            items = tag_schema,
            default = defaults.constant_tags
        }
    },
}

local _M = {
    version = 0.1,
    priority = 495,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
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

    if entry.constant_tags and #entry.constant_tags > 0 then
        for _, tag in ipairs(entry.constant_tags) do
            core.table.insert(tags, tag)
        end
    end

    local variable_tags = {
        {"route_name", entry.route_id},
        {"path", entry.path},
        {"method", entry.method},
        {"service_name", entry.service_id},
        {"consumer", entry.consumer and entry.consumer.username},
        {"balancer_ip", entry.balancer_ip},
        {"response_status", entry.response.status},
        {
            "response_status_class",
            entry.response.status and floor(entry.response.status / 100) .. "xx"
        },
        {"scheme", entry.scheme}
    }

    for _, tag in ipairs(variable_tags) do
        local key, value = unpack(tag)
        if value and value ~= "" then
            core.table.insert(tags, key .. ":" .. value)
        end
    end

    if #tags > 0 then
        return "|#" .. concat(tags, ',')
    end

    return ""
end


local function send_metric_over_udp(entry, metadata)
    local err_msg
    local sock = udp()
    local host, port = metadata.value.host, metadata.value.port

    local ok, err = sock:setpeername(host, port)
    if not ok then
        return false, "failed to connect to UDP server: host[" .. host
                      .. "] port[" .. tostring(port) .. "] err: " .. err
    end

    -- Generate prefix & suffix according dogstatsd udp data format.
    local suffix = generate_tag(entry, metadata.value.constant_tags)
    local prefix = metadata.value.namespace
    if prefix ~= "" then
        prefix = prefix .. "."
    end

    -- request counter
    ok, err = sock:send(format("%s:%s|%s%s", prefix .. "request.counter", 1, "c", suffix))
    if not ok then
        err_msg = "error sending request.counter: " .. err
        core.log.error("failed to report request count to dogstatsd server: host[" .. host
                       .. "] port[" .. tostring(port) .. "] err: " .. err)
    end

    -- request latency histogram
    ok, err = sock:send(format("%s:%s|%s%s", prefix .. "request.latency",
                               entry.latency, "h", suffix))
    if not ok then
        err_msg = "error sending request.latency: " .. err
        core.log.error("failed to report request latency to dogstatsd server: host["
                       .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
    end

    -- upstream latency
    if entry.upstream_latency then
        ok, err = sock:send(format("%s:%s|%s%s", prefix .. "upstream.latency",
                                   entry.upstream_latency, "h", suffix))
        if not ok then
            err_msg = "error sending upstream.latency: " .. err
            core.log.error("failed to report upstream latency to dogstatsd server: host["
                           .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
        end
    end

    -- apisix_latency
    ok, err = sock:send(format("%s:%s|%s%s", prefix .. "apisix.latency",
                               entry.apisix_latency, "h", suffix))
    if not ok then
        err_msg = "error sending apisix.latency: " .. err
        core.log.error("failed to report apisix latency to dogstatsd server: host[" .. host
                       .. "] port[" .. tostring(port) .. "] err: " .. err)
    end

    -- request body size timer
    ok, err = sock:send(format("%s:%s|%s%s", prefix .. "ingress.size",
                               entry.request.size, "ms", suffix))
    if not ok then
        err_msg = "error sending ingress.size: " .. err
        core.log.error("failed to report req body size to dogstatsd server: host[" .. host
                       .. "] port[" .. tostring(port) .. "] err: " .. err)
    end

    -- response body size timer
    ok, err = sock:send(format("%s:%s|%s%s", prefix .. "egress.size",
                               entry.response.size, "ms", suffix))
    if not ok then
        err_msg = "error sending egress.size: " .. err
        core.log.error("failed to report response body size to dogstatsd server: host["
                       .. host .. "] port[" .. tostring(port) .. "] err: " .. err)
    end

    ok, err = sock:close()
    if not ok then
        core.log.error("failed to close the UDP connection, host[",
                       host, "] port[", port, "] ", err)
    end

    if not err_msg then
        return true
    end

    return false, err_msg
end


local function push_metrics(entries)
    -- Fetching metadata details
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    if not metadata then
        core.log.info("received nil metadata: using metadata defaults: ",
                      core.json.delay_encode(defaults, true))
        metadata = {}
        metadata.value = defaults
    end
    core.log.info("sending batch metrics to dogstatsd: ", metadata.value.host,
                  ":", metadata.value.port)

    for i = 1, #entries do
        local ok, err = send_metric_over_udp(entries[i], metadata)
        if not ok then
            return false, err, i
        end
    end

    return true
end


function _M.log(conf, ctx)
    local entry = fetch_log(ngx, {})
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

    if conf.include_path then
        if ctx.curr_req_matched and ctx.curr_req_matched._path then
            entry.path = ctx.curr_req_matched._path
        end
    end

    if conf.include_method then
        entry.method = ctx.var.method
    end

    if conf.constant_tags and #conf.constant_tags > 0 then
        entry.constant_tags = core.table.clone(conf.constant_tags)
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, push_metrics)
end

return _M
