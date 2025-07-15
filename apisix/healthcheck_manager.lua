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
local healthcheck
local events = require("apisix.events")
local tab_clone = core.table.clone
local inspect = require("inspect")
local timer_every = ngx.timer.every
local _M = {
    working_pool = {},     -- resource_path -> {version = ver, checker = checker}
    waiting_pool = {}      -- resource_path -> resource_ver
}

local function fetch_latest_conf(resource_path)
    -- Extract resource type and ID from path
    local resource_type, id = resource_path:match("^/apisix/([^/]+)/([^/]+)$")
    if not resource_type or not id then
        core.log.error("invalid resource path: ", resource_path)
        return nil
    end

    local key
    if resource_type == "upstreams" or resource_type == "upstream" then
        key = "/upstreams"
    elseif resource_type == "routes" or resource_type == "route" then
        key = "/routes"
    else
        core.log.error("unsupported resource type: ", resource_type)
        return nil
    end

    local data = core.config.fetch_created_obj(key)
    if not data then
        core.log.error("failed to fetch configuration for type: ", key)
        return nil
    end
    -- Get specific resource by ID
    local resource = data:get(id)
    if not resource then
        core.log.error("resource not found: ", id, " in ", key)
        return nil
    end

    return resource
end

local function get_healthcheck_name(value)
    return "upstream#" .. value.key
end

local function create_checker(up_conf)
    core.log.warn("creating healthchecker for upstream: ", up_conf.key)
    if not healthcheck then
        healthcheck = require("resty.healthcheck")
    end

    core.log.warn("creating new healthchecker for ", up_conf.key)

    local checker, err = healthcheck.new({
        name = get_healthcheck_name(up_conf.parent),
        shm_name = "upstream-healthcheck",
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
    -- Check working pool first
    local working_item = _M.working_pool[resource_path]
    if working_item and working_item.version == resource_ver then
        return working_item.checker
    end

    if _M.waiting_pool[resource_path] == resource_ver then
        return nil
    end

    -- Add to waiting pool with version
    core.log.warn("adding ", resource_path, " to waiting pool with version: ", resource_ver)
    _M.waiting_pool[resource_path] = resource_ver
    return nil
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
            if resource_ver ~= res_conf.modifiedIndex then
                goto continue
            end
            local checker = create_checker(res_conf.value.upstream or res_conf.value)
            if not checker then
                goto continue
            end
            _M.working_pool[resource_path] = {
                version = resource_ver,
                checker = checker
            }
        end


        core.log.warn("created healthchecker for ", resource_path, " version: ", resource_ver)
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
            _M.working_pool[resource_path] = nil
            goto continue
        end

        local current_ver = res_conf.modifiedIndex .. "#" .. tostring(res_conf.value) .. "#" ..
                            tostring(res_conf.value._nodes_ver or '')
        if item.version ~= current_ver then
            item.checker:delayed_clear(10)
            item.checker:stop()
            _M.working_pool[resource_path] = nil
        end

        ::continue::
    end
end

function _M.init_worker()
    timer_every(1, _M.timer_create_checker)
    timer_every(60, _M.timer_working_pool_check)
end

return _M
