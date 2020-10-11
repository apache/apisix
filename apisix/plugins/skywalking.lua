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
local sw_tracer = require("skywalking.tracer")
local core = require("apisix.core")
local process = require("ngx.process")
local ngx = ngx
local math = math
local select = select
local type = type
local require = require

local plugin_name = "skywalking"
local DEFAULT_ENDPOINT_ADDR = "http://127.0.0.1:12800"


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
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = -1100, -- last running plugin, but before serverless post func
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    core.log.debug("rewrite phase of skywalking plugin")
    ctx.skywalking_sample = false
    if conf.sample_ratio == 1 or math.random() <= conf.sample_ratio then
        ctx.skywalking_sample = true
        sw_tracer:start("upstream service")
        core.log.info("tracer start")
        return
    end

    core.log.info("miss sampling, ignore")
end


function _M.body_filter(conf, ctx)
    if ctx.skywalking_sample and ngx.arg[2] then
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


local function try_read_attr(t, ...)
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        if type(t) ~= "table" then
            return nil
        end
        t = t[attr]
    end

    return t
end


function _M.init()
    if process.type() ~= "worker" and process.type() ~= "single" then
        return
    end

    --todo: maybe need to fetch them from plugin-metadata
    local metadata_buffer = ngx.shared.tracing_buffer
    metadata_buffer:set('serviceName', 'User Service Name')
    metadata_buffer:set('serviceInstanceName', 'User Service Instance Name')

    local local_conf = core.config.local_conf()
    local local_endpoint_addr = try_read_attr(local_conf, "plugin_attr",
                                              plugin_name)

    local endpoint_addr = local_endpoint_addr or DEFAULT_ENDPOINT_ADDR
    require("skywalking.client"):startBackendTimer(endpoint_addr)
    core.log.info("start the backend timer, report to: ", endpoint_addr)
end


return _M
