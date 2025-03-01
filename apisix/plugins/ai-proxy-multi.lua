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
local plugin = require("apisix.plugin")
local base = require("apisix.plugins.ai-proxy.base")

local require = require
local pcall = pcall
local ipairs = ipairs
local type = type

local internal_server_error = ngx.HTTP_INTERNAL_SERVER_ERROR
local priority_balancer = require("apisix.balancer.priority")

local pickers = {}
local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})

local plugin_name = "ai-proxy-multi"
local _M = {
    version = 0.5,
    priority = 998,
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
    for _, provider in ipairs(conf.providers) do
        local ai_driver = pcall(require, "apisix.plugins.ai-drivers." .. provider.name)
        if not ai_driver then
            return false, "provider: " .. provider.name .. " is not supported."
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

    return core.schema.check(schema.ai_proxy_multi_schema, conf)
end


local function transform_providers(new_providers, provider)
    if not new_providers._priority_index then
        new_providers._priority_index = {}
    end

    if not new_providers[provider.priority] then
        new_providers[provider.priority] = {}
        core.table.insert(new_providers._priority_index, provider.priority)
    end

    new_providers[provider.priority][provider.name] = provider.weight
end


local function create_server_picker(conf, ups_tab)
    local picker = pickers[conf.balancer.algorithm] -- nil check
    if not picker then
        pickers[conf.balancer.algorithm] = require("apisix.balancer." .. conf.balancer.algorithm)
        picker = pickers[conf.balancer.algorithm]
    end
    local new_providers = {}
    for i, provider in ipairs(conf.providers) do
        transform_providers(new_providers, provider)
    end

    if #new_providers._priority_index > 1 then
        core.log.info("new providers: ", core.json.delay_encode(new_providers))
        return priority_balancer.new(new_providers, ups_tab, picker)
    end
    core.log.info("upstream nodes: ",
                core.json.delay_encode(new_providers[new_providers._priority_index[1]]))
    return picker.new(new_providers[new_providers._priority_index[1]], ups_tab)
end


local function get_provider_conf(providers, name)
    for i, provider in ipairs(providers) do
        if provider.name == name then
            return provider
        end
    end
end


local function pick_target(ctx, conf, ups_tab)
    if ctx.ai_balancer_try_count > 1 then
        if ctx.server_picker and ctx.server_picker.after_balance then
            ctx.server_picker.after_balance(ctx, true)
        end
    end

    local server_picker = ctx.server_picker
    if not server_picker then
        server_picker = lrucache_server_picker(ctx.matched_route.key, plugin.conf_version(conf),
                                               create_server_picker, conf, ups_tab)
    end
    if not server_picker then
        return internal_server_error, "failed to fetch server picker"
    end

    local provider_name = server_picker.get(ctx)
    local provider_conf = get_provider_conf(conf.providers, provider_name)

    ctx.balancer_server = provider_name
    ctx.server_picker = server_picker

    return provider_name, provider_conf
end


local function get_load_balanced_provider(ctx, conf, ups_tab, request_table)
    ctx.ai_balancer_try_count = (ctx.ai_balancer_try_count or 0) + 1
    local provider_name, provider_conf
    if #conf.providers == 1 then
        provider_name = conf.providers[1].name
        provider_conf = conf.providers[1]
    else
        provider_name, provider_conf = pick_target(ctx, conf, ups_tab)
    end

    core.log.info("picked provider: ", provider_name)
    if provider_conf.model then
        request_table.model = provider_conf.model
    end

    provider_conf.__name = provider_name
    return provider_name, provider_conf
end

local function get_model_name(...)
end


local function proxy_request_to_llm(conf, request_table, ctx)
    local ups_tab = {}
    local algo = core.table.try_read_attr(conf, "balancer", "algorithm")
    if algo == "chash" then
        local hash_on = core.table.try_read_attr(conf, "balancer", "hash_on")
        local hash_key = core.table.try_read_attr(conf, "balancer", "key")
        ups_tab["key"] = hash_key
        ups_tab["hash_on"] = hash_on
    end

    ::retry::
    local provider, provider_conf = get_load_balanced_provider(ctx, conf, ups_tab, request_table)
    local extra_opts = {
        endpoint = core.table.try_read_attr(provider_conf, "override", "endpoint"),
        query_params = provider_conf.auth.query or {},
        headers = (provider_conf.auth.header or {}),
        model_options = provider_conf.options,
    }

    local ai_driver = require("apisix.plugins.ai-drivers." .. provider)
    local res, err, httpc = ai_driver:request(conf, request_table, extra_opts)
    if not res then
        if (ctx.ai_balancer_try_count or 0) < 1 then
            core.log.warn("failed to send request to LLM: ", err, ". Retrying...")
            goto retry
        end
        return nil, err, nil
    end

    request_table.model = provider_conf.model
    return res, nil, httpc
end


_M.access = base.new(proxy_request_to_llm, get_model_name)


return _M
