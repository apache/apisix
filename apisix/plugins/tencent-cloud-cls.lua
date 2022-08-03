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
local cls_sdk = require("apisix.plugins.tencent-cloud-cls.cls-sdk")
local random = math.random
local ngx = ngx
math.randomseed(ngx.time() + ngx.worker.pid())

local plugin_name = "tencent-cloud-cls"
local batch_processor_manager = bp_manager_mod.new(plugin_name)
local schema = {
    type = "object",
    properties = {
        cls_host = { type = "string" },
        cls_topic = { type = "string" },
        -- https://console.cloud.tencent.com/capi
        secret_id = { type = "string" },
        secret_key = { type = "string" },
        sample_rate = { type = "integer", minimum = 1, maximum = 100, default = 100 },
        include_req_body = { type = "boolean", default = false },
        include_resp_body = { type = "boolean", default = false },
    },
    required = { "cls_host", "cls_topic", "secret_id", "secret_key" }
}

local _M = {
    version = 0.1,
    priority = 413,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.body_filter(conf, ctx)
    -- sample if set
    if conf.sample_rate < 100 and random(1, 100) > conf.sample_rate then
        core.log.debug("not sampled")
        return
    end
    log_util.collect_body(conf, ctx)
    ctx.cls_sample = true
end

function _M.log(conf, ctx)
    -- sample if set
    if ctx.cls_sample == nil then
        core.log.debug("not sampled")
        return
    end
    local entry = log_util.get_full_log(ngx, conf)
    if not entry.route_id then
        entry.route_id = "no-matched"
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return cls_sdk.send_to_cls(conf.secret_id, conf.secret_key, conf.cls_host, conf.cls_topic, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end

return _M
