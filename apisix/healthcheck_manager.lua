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
local ipairs   = ipairs
local pcall   = pcall
local exiting      = ngx.worker.exiting
local pairs    = pairs
local tostring = tostring
local core = require("apisix.core")
local config_local   = require("apisix.core.config_local")
local healthcheck
local events = require("apisix.events")
local tab_clone = core.table.clone
local timer_every = ngx.timer.every
local ngx_re      = require('ngx.re')
local jp = require("jsonpath")
local string_sub     = string.sub
local inspect = require("inspect")
local _M = {}
local working_pool = {}     -- resource_path -> {version = ver, checker = checker}
local waiting_pool = {}      -- resource_path -> resource_ver

local DELAYED_CLEAR_TIMEOUT = 10
local healthcheck_shdict_name = "upstream-healthcheck"
local is_http = ngx.config.subsystem == "http"
if not is_http then
    healthcheck_shdict_name = healthcheck_shdict_name .. "-" .. ngx.config.subsystem
end


local function get_healthchecker_name(value)
    return "upstream#" .. (value.resource_key or value.upstream.resource_key)
end
_M.get_healthchecker_name = get_healthchecker_name

local function remove_etcd_prefix(key)
    local prefix = ""
    local local_conf = config_local.local_conf()
    local role = core.table.try_read_attr(local_conf, "deployment", "role")
    local provider = core.table.try_read_attr(local_conf, "deployment", "role_" ..
    role, "config_provider")
    if provider == "etcd" and local_conf.etcd and local_conf.etcd.prefix then
        prefix = local_conf.etcd.prefix
    end
    return string_sub(key, #prefix + 1)
end

local function parse_path(resource_full_path)
    local resource_path_parts = ngx_re.split(resource_full_path, "#")
    local resource_path = resource_path_parts[1] or resource_full_path
    local resource_sub_path = resource_path_parts[2] or ""
    return resource_path, resource_sub_path
end

local function fetch_latest_conf(resource_path)
    -- if resource path contains json path, extract out the prefix
    -- for eg: extracts /routes/1 from /routes/1#plugins.abc
    resource_path = parse_path(resource_path)
    local resource_type, id
    -- Handle both formats:
    -- 1. /<etcd-prefix>/<resource_type>/<id>
    -- 2. /<resource_type>/<id>
    resource_path = remove_etcd_prefix(resource_path)
    resource_type, id = resource_path:match("^/([^/]+)/([^/]+)$")
    if not resource_type or not id then
        core.log.error("invalid resource path: ", resource_path)
        return nil
    end

    local key
    if resource_type == "upstreams" then
        key = "/upstreams"
    elseif resource_type == "routes" then
        key = "/routes"
    elseif resource_type == "services" then
        key = "/services"
    elseif resource_type == "stream_routes" then
        key = "/stream_routes"
    else
        core.log.error("unsupported resource type: ", resource_type)
        return nil
    end

    local data = core.config.fetch_created_obj(key)
    if not data then
        core.log.error("failed to fetch configuration for type: ", key)
        return nil
    end
    local resource = data:get(id)
    if not resource then
        -- this can happen if the resource was deleted
        -- after the this function was called so we don't throw error
        core.log.warn("resource not found: ", id, " in ", key,
                      "this can happen if the resource was deleted")
        return nil
    end

    return resource
end

function _M.get_nodes_ver(resource_path)
    local res_conf = fetch_latest_conf(resource_path)
    local upstream = res_conf.value.upstream or res_conf.value
    return upstream._nodes_ver
end


function _M.set_nodes_ver_and_nodes(resource_path, nodes_ver, nodes)
    local res_conf = fetch_latest_conf(resource_path)
    local upstream = res_conf.value.upstream or res_conf.value
    upstream._nodes_ver = nodes_ver
    upstream.nodes = nodes
end

local inspect = require("inspect")
function _M.set_nodes_ver_and_dns_value(resource_path, nodes_ver, dns_value)
    local res_conf = fetch_latest_conf(resource_path)
    local upstream = res_conf.value.upstream or res_conf.value
    upstream._nodes_ver = nodes_ver
    upstream.nodes = nodes
    res_conf.value.dns_value = dns_value
    res_conf.value.dns_value.upstream._nodes_ver = nodes_ver
    core.log.info("setting dns value bhai", inspect(res_conf.value.dns_value))
end


local function create_checker(up_conf)
    if not up_conf.checks then
        return nil
    end
    local local_conf = config_local.local_conf()
    if local_conf and local_conf.apisix and local_conf.apisix.disable_upstream_healthcheck then
        core.log.info("healthchecker won't be created: disabled upstream healthcheck")
        return nil
    end
    core.log.info("creating healthchecker for upstream: ", up_conf.resource_key)
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end

    local checker, err = healthcheck.new({
        name = get_healthchecker_name(up_conf),
        shm_name = healthcheck_shdict_name,
        checks = up_conf.checks,
        events_module = events:get_healthcheck_events_modele(),
    })

    if not checker then
        core.log.error("failed to create healthcheck: ", err)
        return nil
    end

    -- Add target nodes
    local host = up_conf.checks and up_conf.checks.active and up_conf.checks.active.host
    local port = up_conf.checks and up_conf.checks.active and up_conf.checks.active.port
    local up_hdr = up_conf.pass_host == "rewrite" and up_conf.upstream_host
    local use_node_hdr = up_conf.pass_host == "node" or nil

    for _, node in ipairs(up_conf.nodes) do
        local host_hdr = up_hdr or (use_node_hdr and node.domain)
        local ok, err = checker:add_target(node.host, port or node.port, host,
                                        true, host_hdr)
        if not ok then
            core.log.error("failed to add healthcheck target: ", node.host, ":",
                          port or node.port, " err: ", err)
        end
    end

    return checker
end


function _M.fetch_checker(resource_path, resource_ver)
    local working_item = working_pool[resource_path]
    if working_item and working_item.version == resource_ver then
        return working_item.checker
    end

    if waiting_pool[resource_path] == resource_ver then
        return nil
    end

    -- Add to waiting pool with version
    core.log.info("adding ", resource_path, " to waiting pool with version: ", resource_ver)
    waiting_pool[resource_path] = resource_ver
    return nil
end


function _M.fetch_node_status(checker, ip, port, hostname)
    -- check if the checker is valid
    if not checker or checker.dead then
        return true
    end

    return checker:get_target_status(ip, port, hostname)
end


local function add_working_pool(resource_path, resource_ver, checker)
    working_pool[resource_path] = {
        version = resource_ver,
        checker = checker
    }
end

local function find_in_working_pool(resource_path, resource_ver)
    local checker = working_pool[resource_path]
    if not checker then
        return nil  -- not found
    end

    if checker.version ~= resource_ver then
        core.log.info("version mismatch for resource: ", resource_path,
                    " current version: ", checker.version, " requested version: ", resource_ver)
        return nil  -- version not match
    end
    return checker
end


function _M.upstream_version(index, nodes_ver)
    core.log.warn("index: ", index, " nodes_ver: ", nodes_ver)
    if not index then
        return
    end
    return index .. tostring(nodes_ver or '')
end


local function get_plugin_name(path)
    -- Extract JSON path (after '#') or use full path
    local json_path = path:match("#(.+)$") or path
    -- Match plugin name in the JSON path segment
    return json_path:match("^plugins%['([^']+)'%]")
        or json_path:match('^plugins%["([^"]+)"%]')
        or json_path:match("^plugins%.([^%.]+)")
end

local function timer_create_checker()
    if core.table.nkeys(waiting_pool) == 0 then
        return
    end

    local waiting_snapshot = tab_clone(waiting_pool)
    for resource_path, resource_ver in pairs(waiting_snapshot) do
        do
            if find_in_working_pool(resource_path, resource_ver) then
                core.log.info("resource: ", resource_path,
                             " already in working pool with version: ",
                               resource_ver)
                goto continue
            end
            local res_conf = fetch_latest_conf(resource_path)
            if not res_conf then
                goto continue
            end
            local upstream
            local plugin_name = get_plugin_name(resource_path)
            if plugin_name and plugin_name ~= "" then
                local _, sub_path = parse_path(resource_path)
                local json_path = "$." .. sub_path
                --- the users of the API pass the jsonpath(in resourcepath) to
                --- upstream_constructor_config which is passed to the
                --- callback construct_upstream to create an upstream dynamically
                local upstream_constructor_config = jp.value(res_conf.value, json_path)
                local plugin = require("apisix.plugins." .. plugin_name)
                upstream = plugin.construct_upstream(upstream_constructor_config)
                upstream.resource_key = resource_path
            else
                core.log.warn("res_conf.value",inspect(res_conf.value))
                upstream = (res_conf.value.dns_value and res_conf.value.dns_value.upstream) or -- dns
                            res_conf.value.upstream or res_conf.value -- service discovery
            end
            local new_version = _M.upstream_version(res_conf.modifiedIndex, upstream._nodes_ver)
            core.log.warn("ashish bhai upar se aaya upstream with node version ", upstream._nodes_ver)
            core.log.info("checking waiting pool for resource: ", resource_path,
                    " current version: ", new_version, " requested version: ", resource_ver)
            if resource_ver ~= new_version then
                goto continue
            end

            -- if a checker exists then delete it before creating a new one
            local existing_checker = working_pool[resource_path]
            if existing_checker then
                existing_checker.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
                existing_checker.checker:stop()
                core.log.info("releasing existing checker: ", tostring(existing_checker.checker),
                              " for resource: ", resource_path, " and version: ",
                              existing_checker.version)
            end
            local checker = create_checker(upstream)
            if not checker then
                goto continue
            end
            core.log.info("create new checker: ", tostring(checker), " for resource: ",
                        resource_path, " and version: ", resource_ver)
            add_working_pool(resource_path, resource_ver, checker)
        end

        ::continue::
        waiting_pool[resource_path] = nil
    end
end


local function timer_working_pool_check()
    if core.table.nkeys(working_pool) == 0 then
        return
    end

    local working_snapshot = tab_clone(working_pool)
    for resource_path, item in pairs(working_snapshot) do
        --- remove from working pool if resource doesn't exist
        local res_conf = fetch_latest_conf(resource_path)
        if not res_conf then
            goto continue
        end
        local upstream
        local plugin_name = get_plugin_name(resource_path)
        if plugin_name and plugin_name ~= "" then
            local _, sub_path = parse_path(resource_path)
            local json_path = "$." .. sub_path
            --- the users of the API pass the jsonpath(in resourcepath) to
            --- upstream_constructor_config which is passed to the
            --- callback construct_upstream to create an upstream dynamically
            local upstream_constructor_config = jp.value(res_conf.value, json_path)
            local plugin = require("apisix.plugins." .. plugin_name)
            upstream = plugin.construct_upstream(upstream_constructor_config)
            upstream.resource_key = resource_path
        else
            upstream = (res_conf.value.dns_value and res_conf.value.dns_value.upstream) or -- dns
                        res_conf.value.upstream or res_conf.value -- service discovery
        end
        local need_destroy = true
        if res_conf and res_conf.value then
            core.log.warn("ashish bhai upar se aaya upstream with node version ", upstream._nodes_ver)
            local current_ver = _M.upstream_version(res_conf.modifiedIndex,
                                                    upstream._nodes_ver)
            core.log.info("checking working pool for resource: ", resource_path,
                        " current version: ", current_ver, " item version: ", item.version)
            if item.version == current_ver then
                need_destroy = false
            end
        end

        if need_destroy then
            working_pool[resource_path] = nil
            item.checker.dead = true
            item.checker:delayed_clear(DELAYED_CLEAR_TIMEOUT)
            item.checker:stop()
            core.log.info("try to release checker: ", tostring(item.checker), " for resource: ",
                        resource_path, " and version : ", item.version)
        end
    ::continue::
    end
end

function _M.init_worker()
    local timer_create_checker_running = false
    local timer_working_pool_check_running = false
    timer_every(1, function ()
        if not exiting() then
            if timer_create_checker_running then
                core.log.warn("timer_create_checker is already running, skipping this iteration")
                return
            end
            timer_create_checker_running = true
            local ok, err = pcall(timer_create_checker)
            if not ok then
                core.log.error("failed to run timer_create_checker: ", err)
            end
            timer_create_checker_running = false
        end
    end)
    timer_every(1, function ()
        if not exiting() then
            if timer_working_pool_check_running then
                core.log.warn("timer_working_pool_check is already running skipping iteration")
                return
            end
            timer_working_pool_check_running = true
            local ok, err = pcall(timer_working_pool_check)
            if not ok then
                core.log.error("failed to run timer_working_pool_check: ", err)
            end
            timer_working_pool_check_running = false
        end
    end)
end

return _M
