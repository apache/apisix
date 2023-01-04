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
local utils = require("apisix.admin.utils")
local setmetatable = setmetatable


local _M = {
    name = "",
    handlers = {},
    version = 0.2,
    need_v3_filter = true,
    -- TODO: this will be removed after all methods of resources refactored
    valid_methods = { get = {} },
}


local resources = {
    routes              = { name = "routes", handlers = { get = {} } },
    services            = { name = "services", handlers = { get = {} } },
    upstreams           = { name = "upstreams", handlers = { get = {} } },
    consumers           = { name = "consumers", handlers = { get = {} } },
    ssls                = { name = "ssls", handlers = { get = {} } },
    plugins             = { name = "plugins", handlers = { get = {} } },
    protos              = { name = "protos", handlers = { get = {} } },
    global_rules        = { name = "global_rules", handlers = { get = {} } },
    stream_routes       = { name = "stream_routes", handlers = { get = {} } },
    plugin_metadata     = { name = "plugin_metadata", handlers = { get = {} } },
    plugin_configs      = { name = "plugin_configs", handlers = { get = {} } },
    consumer_groups     = { name = "consumer_groups", handlers = { get = {} } },
    secrets             = { name = "secrets", handlers = { get = {} } },
}


function _M:new(name)
    local m = {}
    setmetatable(m, self)
    self.__index = self
    if not resources[name] then
        core.log.error("there are no resources named: ", name)
    else
        m.name = name
        m.handlers = resources[name].handlers
    end
    return m
end


-- Copy from local function with the same name from apisix.admin.secrets
-- TODO: merge the two into one
local function split_typ_and_id(id, sub_path)
    local uri_segs = core.utils.split_uri(sub_path)
    local typ = id
    local id = nil
    if #uri_segs > 0 then
        id = uri_segs[1]
    end
    return typ, id
end


function _M.get(id, conf, sub_path)
    local key = "/" .. _M.name
    if id then
        -- `/secrets`
        if id == resources.secrets.name then
            key = key .. "/"
            local typ, id = split_typ_and_id(id, sub_path)
            if id then
                key = key .. typ
                key = key .. "/" .. id
            end
        else
            key = key .. "/" .. id
        end
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get [", key, "] from etcd: ", err)
        return 503, {error_msg = err}
    end

    -- `/ssls`: not return private key for security
    if _M.name == resources.ssls.name and res.body and res.body.node and res.body.node.value then
        res.body.node.value.key = nil
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


return _M
