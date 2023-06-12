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
local math = math
local pairs = pairs


local plugin_name = "tencent-cloud-cls"
local batch_processor_manager = bp_manager_mod.new(plugin_name)
local schema = {
    type = "object",
    properties = {
        cls_host = { type = "string" },
        cls_topic = { type = "string" },
        secret_id = { type = "string" },
        secret_key = { type = "string" },
        sample_ratio = {
            type = "number",
            minimum = 0.00001,
            maximum = 1,
            default = 1
        },
        include_req_body = { type = "boolean", default = false },
        include_resp_body = { type = "boolean", default = false },
        global_tag = { type = "object" },
        log_format = {type = "object"},
    },
    encrypt_fields = {"secret_key"},
    required = { "cls_host", "cls_topic", "secret_id", "secret_key" }
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 397,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
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


function _M.access(conf, ctx)
    ctx.cls_sample = false
    if conf.sample_ratio == 1 or math.random() < conf.sample_ratio then
        core.log.debug("cls sampled")
        ctx.cls_sample = true
        return
    end
end


function _M.body_filter(conf, ctx)
    if ctx.cls_sample then
        log_util.collect_body(conf, ctx)
    end
end


function _M.log(conf, ctx)
    -- sample if set
    if not ctx.cls_sample then
        core.log.debug("cls not sampled, skip log")
        return
    end

    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if conf.global_tag then
        for k, v in pairs(conf.global_tag) do
            entry[k] = v
        end
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        local sdk, err = cls_sdk.new(conf.cls_host, conf.cls_topic, conf.secret_id, conf.secret_key)
        if err then
            core.log.error("init sdk failed err:", err)
            return false, err
        end
        return sdk:send_to_cls(entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end


return _M
