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
local pairs    = pairs
local tostring = tostring
local core = require("apisix.core")
local config_local   = require("apisix.core.config_local")
local healthcheck
local events = require("apisix.events")
local tab_clone = core.table.clone
local timer_every = ngx.timer.every
local _M = {
    working_pool = {},     -- resource_path -> {version = ver, checker = checker}
    waiting_pool = {}      -- resource_path -> resource_ver
}
local healthcheck_shdict_name = "upstream-healthcheck"
local is_http = ngx.config.subsystem == "http"
if not is_http then
    healthcheck_shdict_name = healthcheck_shdict_name .. "-" .. ngx.config.subsystem
end
local function fetch_latest_conf(resource_path)
    local resource_type, id
    -- Handle both formats:
    -- 1. /apisix/<resource_type>/<id>
    -- 2. /<resource_type>/<id>
    if resource_path:find("^/apisix/") then
        resource_type, id = resource_path:match("^/apisix/([^/]+)/([^/]+)$")
    else
        resource_type, id = resource_path:match("^/([^/]+)/([^/]+)$")
    end
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
        core.log.warn("resource not found: ", id, " in ", key)
        return nil
    end

    return resource
end

local function get_healthcheck_name(value)
    return "upstream#" .. value.key
end

local function create_checker(up_conf)
    local local_conf = config_local.local_conf()
    if local_conf and local_conf.apisix and local_conf.apisix.disable_upstream_healthcheck then
        core.log.info("healthchecker won't be created: disabled upstream healthcheck")
        return nil
    end
    core.log.warn("creating healthchecker for upstream: ", up_conf.key)
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end

    core.log.warn("creating new healthchecker for ", up_conf.key)

    local checker, err = healthcheck.new({
        name = get_healthcheck_name(up_conf.parent),
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

function _M.fetch_checker(upstream)
    if not upstream or not upstream.checks then
        return nil
    end

    local parent = upstream.parent
    local resource_path = parent.key or upstream.key
    local resource_ver = (upstream.modifiedIndex or parent.modifiedIndex)
                          .. tostring(upstream._nodes_ver or '')
    -- Check working pool first
    local working_item = _M.working_pool[resource_path]
    if working_item and working_item.version == resource_ver then
        return working_item.checker
    end

    if _M.waiting_pool[resource_path] == resource_ver then
        return nil
    end

    -- Add to waiting pool with version
    core.log.info("adding ", resource_path, " to waiting pool with version: ", resource_ver)
    _M.waiting_pool[resource_path] = resource_ver
    return nil
end

function _M.fetch_node_status(checker, ip, port, hostname)
    -- check if the checker is valid
    if not checker or checker.dead then
        return true
    end

    return checker:get_target_status(ip, port, hostname)
end
function _M.timer_create_checker()
    if core.table.nkeys(_M.waiting_pool) == 0 then
        return
    end

    local waiting_snapshot = tab_clone(_M.waiting_pool)
    for resource_path, resource_ver in pairs(waiting_snapshot) do
        local res_conf = fetch_latest_conf(resource_path)
        if not res_conf then
            goto continue
        end
        do
            local upstream = res_conf.value.upstream or res_conf.value
            local new_version = res_conf.modifiedIndex .. tostring(upstream._nodes_ver or '')
            core.log.warn("checking waiting pool for resource: ", resource_path,
                    " current version: ", new_version, " requested version: ", resource_ver)
            if resource_ver ~= new_version then
                goto continue
            end
            local checker = create_checker(upstream)
            if not checker then
                goto continue
            end
            _M.working_pool[resource_path] = {
                version = resource_ver,
                checker = checker
            }
            core.log.info("create new checker: ", tostring(checker))
        end

        ::continue::
        _M.waiting_pool[resource_path] = nil
    end
end

function _M.timer_working_pool_check()
    if core.table.nkeys(_M.working_pool) == 0 then
        return
    end

    local working_snapshot = tab_clone(_M.working_pool)
    for resource_path, item in pairs(working_snapshot) do
        local res_conf = fetch_latest_conf(resource_path)
        if not res_conf then
            item.checker:delayed_clear(10)
            item.checker:stop()
            core.log.info("try to release checker: ", tostring(item.checker))
            _M.working_pool[resource_path] = nil
            goto continue
        end
        local current_ver = res_conf.modifiedIndex ..  tostring(res_conf.value._nodes_ver or '')
        core.log.info("checking working pool for resource: ", resource_path,
                    " current version: ", current_ver, " item version: ", item.version)
        if item.version ~= current_ver then
            item.checker:delayed_clear(10)
            item.checker:stop()
            core.log.info("try to release checker: ", tostring(item.checker))
            _M.working_pool[resource_path] = nil
        end

        ::continue::
    end
end

function _M.init_worker()
    timer_every(1, _M.timer_create_checker)
    timer_every(1, _M.timer_working_pool_check)
end

return _M
