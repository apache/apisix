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
local ipmatcher  = require("resty.ipmatcher")
local healthcheck_manager = require("apisix.healthcheck_manager")
local resource = require("apisix.resource")
local tonumber = tonumber
local pairs = pairs

local require = require
local pcall = pcall
local ipairs = ipairs
local type = type

local priority_balancer = require("apisix.balancer.priority")
local endpoint_regex = "^(https?)://([^:/]+):?(%d*)/?.*$"

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

local function fallback_strategy_has(strategy, name)
    if not strategy then
        return false
    end

    if type(strategy) == "string" then
        return strategy == name
    end

    if type(strategy) == "table" then
        for _, v in ipairs(strategy) do
            if v == name then
                return true
            end
        end
    end

    return false
end


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
        local endpoint = instance and instance.override and instance.override.endpoint
        if endpoint then
            local scheme, host, _ = endpoint:match(endpoint_regex)
            if not scheme or not host  then
                return false, "invalid endpoint"
            end
        end
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

local function parse_domain_for_node(node)
    local host = node.domain or node.host
    if not ipmatcher.parse_ipv4(host)
       and not ipmatcher.parse_ipv6(host)
    then
        node.domain = host

        local ip, err = core.resolver.parse_domain(host)
        if ip then
            node.host = ip
        end

        if err then
            core.log.error("dns resolver domain: ", host, " error: ", err)
        end
    end
end


local function resolve_endpoint(instance_conf)
    local scheme, host, port
    local endpoint = core.table.try_read_attr(instance_conf, "override", "endpoint")
    if endpoint then
        scheme, host, port = endpoint:match(endpoint_regex)
        if port == "" then
            port = (scheme == "https") and "443" or "80"
        end
        port = tonumber(port)
    else
        local ai_driver = require("apisix.plugins.ai-drivers." .. instance_conf.provider)
        -- built-in ai driver always use https
        scheme = "https"
        host = ai_driver.host
        port = ai_driver.port
    end
    local new_node = {
        host = host,
        port = tonumber(port),
        scheme = scheme,
    }
    parse_domain_for_node(new_node)

    -- Compare with existing node to see if anything changed
    local old_node = instance_conf._dns_value
    local nodes_changed = not old_node or
                         old_node.host ~= new_node.host

    -- Only update if something changed
    if nodes_changed then
        instance_conf._dns_value = new_node
        instance_conf._nodes_ver = (instance_conf._nodes_ver or 0) + 1
        core.log.info("DNS resolution changed for instance: ", instance_conf.name,
                     " new node: ", core.json.delay_encode(new_node))
    end
end


local function get_checkers_status_ver(checkers)
    local status_ver_total = 0
    for _, checker in pairs(checkers) do
        status_ver_total = status_ver_total + checker.status_ver
    end
    return status_ver_total
end



local function fetch_health_instances(conf, checkers)
    local instances = conf.instances
    local new_instances = core.table.new(0, #instances)
    if not checkers then
        for _, ins in ipairs(conf.instances) do
            transform_instances(new_instances, ins)
        end
        return new_instances
    end

    for _, ins in ipairs(instances) do
        local checker = checkers[ins.name]
        if checker then
            local host = ins.checks and ins.checks.active and ins.checks.active.host
            local port = ins.checks and ins.checks.active and ins.checks.active.port

            local node = ins._dns_value
            local ok, err = checker:get_target_status(node.host, port or node.port, host)
            if ok then
                transform_instances(new_instances, ins)
            elseif err then
                core.log.warn("failed to get health check target status, addr: ",
                    node.host, ":", port or node.port, ", host: ", host, ", err: ", err)
            end
        else
            transform_instances(new_instances, ins)
        end
    end

    if core.table.nkeys(new_instances) == 0 then
        core.log.warn("all upstream nodes is unhealthy, use default")
        for _, ins in ipairs(instances) do
            transform_instances(new_instances, ins)
        end
    end

    return new_instances
end


local function create_server_picker(conf, ups_tab, checkers)
    local picker = pickers[conf.balancer.algorithm] -- nil check
    if not picker then
        pickers[conf.balancer.algorithm] = require("apisix.balancer." .. conf.balancer.algorithm)
        picker = pickers[conf.balancer.algorithm]
    end

    local new_instances = fetch_health_instances(conf, checkers)
    core.log.info("fetch health instances: ", core.json.delay_encode(new_instances))

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


local inspect = require("inspect")
function _M.construct_upstream(instance)
    local upstream = {}
    -- resolve_endpoint(instance)
    local node = instance._dns_value
    core.log.warn("NODE:::: ", inspect(node))
    if not node then
        return nil, "failed to resolve endpoint for instance: " .. instance.name
    end

    if not node.host or not node.port then
        return nil, "invalid upstream node: " .. core.json.encode(node)
    end

    local node = {
        host = node.host,
        port = node.port,
        scheme = node.scheme,
        weight = instance.weight or 1,
        priority = instance.priority or 0,
        name = instance.name,
    }
    upstream.nodes = {node}
    upstream.checks = instance.checks
    upstream._nodes_ver = instance._nodes_ver
    return upstream
end


local function pick_target(ctx, conf, ups_tab)
    local checkers
    local res_conf = resource.fetch_latest_conf(conf._meta.parent.resource_key)
    if not res_conf then
        return nil, nil, "failed to fetch the parent config"
    end
    core.log.warn("res_conf", inspect(res_conf))
    local instances = res_conf.value.plugins[plugin_name].instances
    core.log.warn("instances:::", inspect(instances))
    for i, instance in ipairs(conf.instances) do
        if instance.checks then
            resolve_endpoint(instance)
            -- json path is 0 indexed so we need to decrement i
            local resource_path = conf._meta.parent.resource_key ..
                                  "#plugins['ai-proxy-multi'].instances[" .. i-1 .. "]"
            local resource_version = conf._meta.parent.resource_version
            if instance._nodes_ver then
                resource_version = resource_version .. instance._nodes_ver
            end
            core.log.warn("instance:::", inspect(instance))
            instances[i]._dns_value = instance._dns_value
            local checker = healthcheck_manager.fetch_checker(resource_path, resource_version)
            checkers = checkers or {}
            checkers[instance.name] = checker
        end
    end

    local version = plugin.conf_version(conf)
    if checkers then
        local status_ver = get_checkers_status_ver(checkers)
        version = version .. "#" .. status_ver
    end

    local server_picker = ctx.server_picker
    if not server_picker then
        server_picker = lrucache_server_picker(ctx.matched_route.key, version,
                                               create_server_picker, conf, ups_tab, checkers)
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
    if conf.fallback_strategy == "instance_health_and_rate_limiting" or -- for backwards compatible
       fallback_strategy_has(conf.fallback_strategy, "rate_limiting") then
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
    ctx.balancer_ip = name
    ctx.bypass_nginx_upstream = true
end


local function retry_on_error(ctx, conf, code)
    if not ctx.server_picker then
        return code
    end
    ctx.server_picker.after_balance(ctx, true)
    if (code == 429 and fallback_strategy_has(conf.fallback_strategy, "http_429")) or
       (code >= 500 and code < 600 and
       fallback_strategy_has(conf.fallback_strategy, "http_5xx")) then
        local name, ai_instance, err = pick_ai_instance(ctx, conf)
        if err then
            core.log.error("failed to pick new AI instance: ", err)
            return 502
        end
        ctx.balancer_ip = name
        ctx.picked_ai_instance_name = name
        ctx.picked_ai_instance = ai_instance
        return
    end
    return code
end

function _M.before_proxy(conf, ctx)
     return base.before_proxy(conf, ctx, function (ctx, conf, code)
        return retry_on_error(ctx, conf, code)
    end)
end

function _M.log(conf, ctx)
    if conf.logging then
        base.set_logging(ctx, conf.logging.summaries, conf.logging.payloads)
    end
end

return _M
