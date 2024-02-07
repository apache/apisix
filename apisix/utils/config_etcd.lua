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

local _M = {}

local function plugins_eq(old, new)
    local old_set = {}
    for _, p in ipairs(old) do
        old_set[p.name] = p
    end

    local new_set = {}
    for _, p in ipairs(new) do
        new_set[p.name] = p
    end

    return core.table.set_eq(old_set, new_set)
end


function _M.sync_local_conf_to_etcd(reset)
    local local_conf = core.config.local_conf()

    local plugins = {}
    for _, name in ipairs(local_conf.plugins) do
        core.table.insert(plugins, {
            name = name,
        })
    end

    for _, name in ipairs(local_conf.stream_plugins) do
        core.table.insert(plugins, {
            name = name,
            stream = true,
        })
    end

    if reset then
        local res, err = core.etcd.get("/plugins")
        if not res then
            core.log.error("failed to get current plugins: ", err)
            return
        end

        if res.status == 404 then
            -- nothing need to be reset
            return
        end

        if res.status ~= 200 then
            core.log.error("failed to get current plugins, status: ", res.status)
            return
        end

        local stored_plugins = res.body.node.value
        local revision = res.body.node.modifiedIndex
        if plugins_eq(stored_plugins, plugins) then
            core.log.info("plugins not changed, don't need to reset")
            return
        end

        core.log.warn("sync local conf to etcd")

        local res, err = core.etcd.atomic_set("/plugins", plugins, nil, revision)
        if not res then
            core.log.error("failed to set plugins: ", err)
        end

        return
    end

    core.log.warn("sync local conf to etcd")

    -- need to store all plugins name into one key so that it can be updated atomically
    local res, err = core.etcd.set("/plugins", plugins)
    if not res then
        core.log.error("failed to set plugins: ", err)
    end
end

return _M
