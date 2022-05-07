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
local require = require
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local process = require("ngx.process")
local sw_tracer = require("skywalking.tracer")
local Span = require("skywalking.span")
local ngx = ngx
local math = math

local plugin_name = "skywalking"
local attr_schema = {
    type = "object",
    properties = {
        service_name = {
            type = "string",
            description = "service name for skywalking",
            default = "APISIX",
        },
        service_instance_name = {
            type = "string",
            description = "User Service Instance Name",
            default = "APISIX Instance Name",
        },
        endpoint_addr = {
            type = "string",
            default = "http://127.0.0.1:12800",
        },
        report_interval = {
            type = "integer",
        },
    },
}

local schema = {
    type = "object",
    properties = {
        sample_ratio = {
            type = "number",
            minimum = 0.00001,
            maximum = 1,
            default = 1
        }
    },
}


local _M = {
    version = 0.1,
    priority = 12010,
    name = plugin_name,
    schema = schema,
    attr_schema = attr_schema,
    run_policy = "prefer_route",
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    core.log.debug("rewrite phase of skywalking plugin")
    ctx.skywalking_sample = false
    if conf.sample_ratio == 1 or math.random() < conf.sample_ratio then
        ctx.skywalking_sample = true
        sw_tracer:start("upstream service")
        core.log.info("tracer start")
        return
    end

    core.log.info("miss sampling, ignore")
end


function _M.delayed_body_filter(conf, ctx)
    if ctx.skywalking_sample and ngx.arg[2] then
        Span.setComponentId(ngx.ctx.exitSpan, 6002)
        Span.setComponentId(ngx.ctx.entrySpan, 6002)
        sw_tracer:finish()
        core.log.info("tracer finish")
    end
end


function _M.log(conf, ctx)
    if ctx.skywalking_sample then
        sw_tracer:prepareForReport()
        core.log.info("tracer prepare for report")
    end
end


function _M.init()
    if process.type() ~= "worker" then
        return
    end

    local local_plugin_info = plugin.plugin_attr(plugin_name)
    local_plugin_info = local_plugin_info and core.table.clone(local_plugin_info) or {}
    local ok, err = core.schema.check(attr_schema, local_plugin_info)
    if not ok then
        core.log.error("failed to check the plugin_attr[", plugin_name, "]",
                       ": ", err)
        return
    end

    core.log.info("plugin attribute: ",
                  core.json.delay_encode(local_plugin_info))

    -- TODO: maybe need to fetch them from plugin-metadata
    local metadata_shdict = ngx.shared.tracing_buffer

    if local_plugin_info.service_instance_name == "$hostname" then
        local_plugin_info.service_instance_name = core.utils.gethostname()
    end

    metadata_shdict:set('serviceName', local_plugin_info.service_name)
    metadata_shdict:set('serviceInstanceName', local_plugin_info.service_instance_name)

    local sk_cli = require("skywalking.client")
    if local_plugin_info.report_interval then
        sk_cli.backendTimerDelay = local_plugin_info.report_interval
    end

    sk_cli:startBackendTimer(local_plugin_info.endpoint_addr)
end


function _M.destroy()
    if process.type() ~= "worker" then
        return
    end

    local sk_cli = require("skywalking.client")
    sk_cli:destroyBackendTimer()
end


return _M
