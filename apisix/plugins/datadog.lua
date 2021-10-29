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
local send_statsd = require("apisix.plugins.udp-logger").send_udp_data
local fetch_info = require("apisix.plugins.prometheus.exporter").parse_info_from_ctx
local format = string.format
local concat = table.concat
local tostring = tostring
local ngx = ngx


local plugin_name = "datadog"

local schema = {
    type = "object",
    properties = {
        sample_rate = {type = "number", default = 1, minimum = 0, maximum = 1},
        tags = {
            type = "array",
            items = {type = "string"},
            default = {"source:apisix"}
        }
    }
}

local metadata_schema = {
    type = "object",
    properties = {
        host = {type = "string", default = "0.0.0.0"},
        port = {type = "integer", minimum = 0, default = 8125},
        namespace = {type = "string", default = "apisix.dev"},
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

local function generate_tag(sample_rate, tag_arr, route_id, service_id, consumer_name, balancer_ip)
    local rate, tags = "", ""

    if sample_rate and sample_rate ~= 1 then
        rate = "|@" .. tostring(sample_rate)
    end

    if tag_arr and #tag_arr > 0 then
        tags = "|#" .. concat(tag_arr, ",")
    end

    if route_id ~= "" then
        tags = tags .. "route_id:" .. route_id
    end

    if service_id ~= "" then
        tags = tags .. "service_id:" .. service_id
    end

    if consumer_name ~= "" then
        tags = tags .. "consumer_name:" .. consumer_name
    end
    if balancer_ip ~= "" then
        tags = tags .. "balancer_ip:" .. balancer_ip
    end

    if tags ~= "" and tags:sub(1, 1) ~= "|" then
        tags = "|#" .. tags
    end

    return rate .. tags

end

function _M.log(conf, ctx)
    core.log.error("conf: ", core.json.delay_encode(conf, true))
    core.log.error("ctx: ", core.json.delay_encode(ctx, true))
    local metadata = plugin.plugin_metadata(plugin_name)
    if not metadata then
        core.log.error("received nil metadata")
    end

    local udp_conf = {
        host = metadata.value.host,
        port = metadata.value.port
    }

    local route_id, service_id, consumer_name, balancer_ip = fetch_info(conf, ctx)
    local prefix = ""

    if metadata.value.namespace ~= "" then
        prefix = prefix .. "."
    end

    local suffix = generate_tag(conf.sample_rate, conf.tags,
                    route_id, service_id, consumer_name, balancer_ip)

    -- request counter
    local ok, err = send_statsd(udp_conf,
                        format("%s:%s|%s%s", prefix .. "request.counter", 1, "c", suffix))
    if not ok then
        core.log.error("failed to send request_count metric to DogStatsD. err: " .. err)
    end


    -- request latency histogram
    local latency = (ngx.now() - ngx.req.start_time()) * 1000
    local ok, err = send_statsd(udp_conf,
                        format("%s:%s|%s%s", prefix .. "request.latency", latency, "h", suffix))
    if not ok then
        core.log.error("failed to send request latency metric to DogStatsD. err: " .. err)
    end

    -- upstream latency
    local apisix_latency = latency
    if ctx.var.upstream_response_time then
        local upstream_latency = ctx.var.upstream_response_time * 1000
        local ok, err = send_statsd(udp_conf,
                format("%s:%s|%s%s", prefix .. "upstream.latency", upstream_latency, "h", suffix))
        if not ok then
            core.log.error("failed to send upstream latency metric to DogStatsD. err: " .. err)
        end
        apisix_latency =  apisix_latency - upstream_latency
        if apisix_latency < 0 then
            apisix_latency = 0
        end
    end

    -- apisix_latency
    local ok, err = send_statsd(udp_conf,
            format("%s:%s|%s%s", prefix .. "apisix.latency", apisix_latency, "h", suffix))
    if not ok then
        core.log.error("failed to send apisix latency metric to DogStatsD. err: " .. err)
    end

    -- request body size timer
    local ok, err = send_statsd(udp_conf,
            format("%s:%s|%s%s", prefix .. "ingress.size", ctx.var.request_length, "ms", suffix))
    if not ok then
        core.log.error("failed to send request body size metric to DogStatsD. err: " .. err)
    end

    -- response body size timer
    local ok, err = send_statsd(udp_conf,
            format("%s:%s|%s%s", prefix .. "egress.size", ctx.var.bytes_sent, "ms", suffix))
    if not ok then
        core.log.error("failed to send response body size metric to DogStatsD. err: " .. err)
    end
end

return _M
