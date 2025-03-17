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
local schema = require("apisix.plugins.ai-proxy.schema")
local base   = require("apisix.plugins.ai-proxy.base")
local plugin = require("apisix.plugin")

local require = require
local pcall = pcall
local ipairs = ipairs
local type = type

local priority_balancer = require("apisix.balancer.priority")

local pickers = {}
local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})

local plugin_name = "ai-proxy-multi"
local _M = {
    version = 0.5,
    priority = 1041,
    name = plugin_name,
    schema = schema.ai_proxy_multi_schema,
}


local function get_chash_key_schema(hash_on)
    if hash_on == "vars" then
        return core.schema.upstream_hash_vars_schema
    end

    if hash_on == "header" or hash_on == "cookie" then
        return core.schema.upstream_hash_header_schema
    end

    if hash_on == "consumer" then
        return nil, nil
    end

    if hash_on == "vars_combinations" then
        return core.schema.upstream_hash_vars_combinations_schema
    end

    return nil, "invalid hash_on type " .. hash_on
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.ai_proxy_multi_schema, conf)
    if not ok then
        return false, err
    end

    for _, instance in ipairs(conf.instances) do
        local ai_driver, err = pcall(require, "apisix.plugins.ai-drivers." .. instance.provider)
        if not ai_driver then
            core.log.warn("fail to require ai provider: ", instance.provider, ", err", err)
            return false, "ai provider: " .. instance.provider .. " is not supported."
        end
    end
    local algo = core.table.try_read_attr(conf, "balancer", "algorithm")
    local hash_on = core.table.try_read_attr(conf, "balancer", "hash_on")
    local hash_key = core.table.try_read_attr(conf, "balancer", "key")

    if type(algo) == "string" and algo == "chash" then
        if not hash_on then
            return false, "must configure `hash_on` when balancer algorithm is chash"
        end

        if hash_on ~= "consumer" and not hash_key then
            return false, "must configure `hash_key` when balancer `hash_on` is not set to cookie"
        end

        local key_schema, err = get_chash_key_schema(hash_on)
        if err then
            return false, "type is chash, err: " .. err
        end

        if key_schema then
            local ok, err = core.schema.check(key_schema, hash_key)
            if not ok then
                return false, "invalid configuration: " .. err
            end
        end
    end

    return ok
end


local function transform_instances(new_instances, instance)
    if not new_instances._priority_index then
        new_instances._priority_index = {}
    end

    if not new_instances[instance.priority] then
        new_instances[instance.priority] = {}
        core.table.insert(new_instances._priority_index, instance.priority)
    end

    new_instances[instance.priority][instance.name] = instance.weight
end


local function create_server_picker(conf, ups_tab)
    local picker = pickers[conf.balancer.algorithm] -- nil check
    if not picker then
        pickers[conf.balancer.algorithm] = require("apisix.balancer." .. conf.balancer.algorithm)
        picker = pickers[conf.balancer.algorithm]
    end
    local new_instances = {}
    for _, ins in ipairs(conf.instances) do
        transform_instances(new_instances, ins)
    end

    if #new_instances._priority_index > 1 then
        core.log.info("new instances: ", core.json.delay_encode(new_instances))
        return priority_balancer.new(new_instances, ups_tab, picker)
    end
    core.log.info("upstream nodes: ",
                core.json.delay_encode(new_instances[new_instances._priority_index[1]]))
    return picker.new(new_instances[new_instances._priority_index[1]], ups_tab)
end


local function get_instance_conf(instances, name)
    for _, ins in ipairs(instances) do
        if ins.name == name then
            return ins
        end
    end
end


local function pick_target(ctx, conf, ups_tab)
    local server_picker = ctx.server_picker
    if not server_picker then
        server_picker = lrucache_server_picker(ctx.matched_route.key, plugin.conf_version(conf),
                                               create_server_picker, conf, ups_tab)
    end
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end
    ctx.server_picker = server_picker

    local instance_name, err = server_picker.get(ctx)
    if err then
        return nil, nil, err
    end
    ctx.balancer_server = instance_name
    if conf.fallback_strategy == "instance_health_and_rate_limiting" then
        local ai_rate_limiting = require("apisix.plugins.ai-rate-limiting")
        for _ = 1, #conf.instances do
            if ai_rate_limiting.check_instance_status(nil, ctx, instance_name) then
                break
            end
            core.log.info("ai instance: ", instance_name,
                             " is not available, try to pick another one")
            server_picker.after_balance(ctx, true)
            instance_name, err = server_picker.get(ctx)
            if err then
                return nil, nil, err
            end
            ctx.balancer_server = instance_name
        end
    end

    local instance_conf = get_instance_conf(conf.instances, instance_name)
    return instance_name, instance_conf
end


local function pick_ai_instance(ctx, conf, ups_tab)
    local instance_name, instance_conf, err
    if #conf.instances == 1 then
        instance_name = conf.instances[1].name
        instance_conf = conf.instances[1]
    else
        instance_name, instance_conf, err = pick_target(ctx, conf, ups_tab)
    end

    core.log.info("picked instance: ", instance_name)
    return instance_name, instance_conf, err
end


function _M.access(conf, ctx)
    local ups_tab = {}
    local algo = core.table.try_read_attr(conf, "balancer", "algorithm")
    if algo == "chash" then
        local hash_on = core.table.try_read_attr(conf, "balancer", "hash_on")
        local hash_key = core.table.try_read_attr(conf, "balancer", "key")
        ups_tab["key"] = hash_key
        ups_tab["hash_on"] = hash_on
    end

    local name, ai_instance, err = pick_ai_instance(ctx, conf, ups_tab)
    if err then
        return 503, err
    end
    ctx.picked_ai_instance_name = name
    ctx.picked_ai_instance = ai_instance
end


_M.before_proxy = base.before_proxy


return _M
