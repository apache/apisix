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
local ngx = ngx
local math = math

local sw_client = require("apisix.plugins.skywalking.client")
local sw_tracer = require("apisix.plugins.skywalking.tracer")

local plugin_name = "skywalking"


local schema = {
    type = "object",
    properties = {
        endpoint = {type = "string"},
        sample_ratio = {type = "number", minimum = 0.00001, maximum = 1, default = 1}
    },
    service_name = {
        type = "string",
        description = "service name for skywalking",
        default = "APISIX",
    },
    required = {"endpoint"}
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
    if conf.sample_ratio == 1 or math.random() < conf.sample_ratio then
        ctx.skywalking_sample = true
        sw_client.heartbeat(conf)
        -- Currently, we can not have the upstream real network address
        sw_tracer.start(ctx, conf.endpoint, "upstream service")
    end
end


function _M.body_filter(conf, ctx)
    if ctx.skywalking_sample and ngx.arg[2] then
        sw_tracer.finish(ctx)
    end
end


function _M.log(conf, ctx)
    if ctx.skywalking_sample then
        sw_tracer.prepareForReport(ctx, conf.endpoint)
    end
end

return _M
