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
local exporter = require("apisix.plugins.prometheus.exporter")
local pairs = pairs
local ipairs = ipairs

local plugin_name = "prometheus"
local schema = {
    type = "object",
    properties = {
        prefer_name = {
            type = "boolean",
            default = false
        }
    },
}


-- Labels that define a metric's identity cannot be disabled: e.g. collapsing
-- `type` would merge request/upstream/apisix latencies into one histogram series.
local structural_labels = {
    http_status = {code = true},
    http_latency = {type = true},
    bandwidth = {type = true},
    llm_latency = {type = true},
    ai_cache_hits_total = {layer = true},
}


local function build_disabled_labels_properties()
    local properties = {}
    for metric_name, metric_labels in pairs(exporter.metric_label_map) do
        local enum = {}
        local structural = structural_labels[metric_name]
        for _, label in ipairs(metric_labels) do
            if not (structural and structural[label]) then
                core.table.insert(enum, label)
            end
        end
        properties[metric_name] = {
            type = "array",
            items = {
                type = "string",
                enum = enum,
            },
        }
    end
    return properties
end


local metadata_schema = {
    type = "object",
    properties = {
        disabled_labels = {
            type = "object",
            properties = build_disabled_labels_properties(),
            additionalProperties = false,
        },
    },
}


local _M = {
    version = 0.2,
    priority = 500,
    name = plugin_name,
    log  = exporter.http_log,
    destroy = exporter.destroy,
    schema = schema,
    metadata_schema = metadata_schema,
    run_policy = "prefer_route",
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.api()
    return exporter.get_api(true)
end


function _M.init()
    local local_conf = core.config.local_conf()
    -- Not `stream_plugins` from config.yaml: that list is only the boot-time
    -- default, and /apisix/plugins in etcd can turn the stream prometheus
    -- plugin on later. This runs whenever the plugin is loaded, so building
    -- `metrics` without the L4 gauges here would leave
    -- collect_stream_zone_metrics() stopped at its first guard for the rest of
    -- the process's life. Whether the stream subsystem runs at all is the
    -- thing that does not change under APISIX.
    local proxy_mode = local_conf.apisix.proxy_mode
    local stream_enabled = proxy_mode == "stream" or proxy_mode == "http&stream"
    exporter.http_init(stream_enabled)
end


return _M
