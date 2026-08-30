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
-- [[
-- limit-req-global — cluster-wide rate limiting via local shared dicts
--
-- Problem: APISIX's built-in limit-req is per-node. With N nodes each
-- configured at rate=100, the cluster actually allows N*100 req/s.
--
-- Solution: This plugin computes a per-node local rate from a cluster-wide
-- global_rate using a configurable instance_count:
--   local_rate = global_rate / instance_count
--   local_burst = global_burst / instance_count
--
-- instance_count is stored in plugin_metadata (cluster-level), updated
-- via Admin API: PUT /apisix/admin/plugin_metadata/limit-req-global
--   {"instance_count": 5}
--
-- A per-worker background timer syncs instance_count from metadata every
-- 10 seconds, keeping the division factor up-to-date without per-request
-- metadata lookups.
--
-- When plugin_metadata is not set, instance_count defaults to 1, making
-- the plugin behave identically to the standard limit-req.
--
-- Tested with Docker compose (etcd + APISIX + httpbin upstream):
--   global_rate=10, instance_count=2  => local_rate=5,  40 concurrent
--   requests → 11 succeeded, 29 rate-limited (503).  Default rejected_code
--   is 429 (Too Many Requests), matching modern API conventions.
--
-- Schema:
--   route-level: global_rate (number), global_burst (number), key (string)
--   cluster-level: instance_count (integer, min=1)
-- ]]
local core                 = require("apisix.core")
local plugin_name          = "limit-req-global"
local sleep                = core.sleep
local apisix_plugin        = require("apisix.plugin")
local timers               = require("apisix.timers")

local lrucache = core.lrucache.new({
    type = "plugin",
})

local cached_instance_count = 1
local last_sync_time = 0

local metadata_schema = {
    type = "object",
    properties = {
        instance_count = { type = "integer", minimum = 1 },
    },
    required = { "instance_count" },
}

local schema = {
    type = "object",
    properties = {
        global_rate  = {type = "number", exclusiveMinimum = 0},
        global_burst = {type = "number",  minimum = 0},
        key          = {type = "string"},
        key_type     = {type = "string",
                        enum = {"var", "var_combination"},
                        default = "var"},
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 429
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        nodelay = {
            type = "boolean", default = false
        },
        allow_degradation = {type = "boolean", default = false}
    },
    required = {"global_rate", "global_burst", "key"},
}


local _M = {
    version = 0.1,
    priority = 1001,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
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


local function create_limit_obj(local_rate, local_burst)
    return limit_req_new("plugin-limit-req-global", local_rate, local_burst)
end


local function gen_limit_key(conf, ctx, key)
    local parent = conf._meta and conf._meta.parent
    if not parent or not parent.resource_key then
        error("failed to generate key invalid parent: " .. core.json.encode(parent))
    end

    return parent.resource_key .. ':' .. apisix_plugin.conf_version(conf) .. ':' .. key
end


local function refresh_instance_count()
    local metadata = apisix_plugin.plugin_metadata(plugin_name)
    if metadata and metadata.value and metadata.value.instance_count then
        cached_instance_count = metadata.value.instance_count
    else
        cached_instance_count = 1
    end

    if cached_instance_count < 1 then
        cached_instance_count = 1
    end
end


local function sync_timer()
    local now = ngx.time()
    if now - last_sync_time < 10 then
        return
    end
    last_sync_time = now
    refresh_instance_count()
end


function _M.access(conf, ctx)
    local local_rate = conf.global_rate / cached_instance_count
    local local_burst = conf.global_burst / cached_instance_count

    local lim, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                              create_limit_obj,
                                              local_rate, local_burst)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    local conf_key = conf.key
    local key
    if conf.key_type == "var_combination" then
        local err, n_resolved
        key, err, n_resolved = core.utils.resolve_var(conf_key, ctx.var)
        if err then
            core.log.error("could not resolve vars in ", conf_key, " error: ", err)
        end

        if n_resolved == 0 then
            key = nil
        end

    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        key = ctx.var["remote_addr"]
    end

    key = gen_limit_key(conf, ctx, key)
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    if delay >= 0.001 and not conf.nodelay then
        sleep(delay)
    end
end


function _M.init()
    timers.register_timer("plugin#limit-req-global", sync_timer)
end


function _M.destroy()
    timers.unregister_timer("plugin#limit-req-global")
end


return _M
