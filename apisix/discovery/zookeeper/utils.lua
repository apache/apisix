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
local zk = require("resty.zookeeper")
local json = require("apisix.core.json")
local ipairs = ipairs
local tonumber = tonumber

local _M = {}

-- Init ZK Clients
function _M.new_zk_client(conf)
    local client, err = zk:new{
        connect_string = conf.connect_string,
        session_timeout = conf.session_timeout,
    }
    if not client then
        core.log.error("failed to create zk client: ", err)
        return nil, err
    end

    client:set_timeout(conf.connect_timeout)

    local ok, err = client:connect()
    if not ok then
        core.log.error("failed to connect to zk: ", err)
        return nil, err
    end

    if conf.auth and conf.auth.creds ~= "" then
        local ok, err = client:add_auth(conf.auth.type, conf.auth.creds)
        if not ok then
            core.log.warn("zk auth failed: ", err)
            return nil, err
        end
    end

    return client
end

-- Recursively Create ZooKeeper Nodes
function _M.create_zk_path(client, path)
    local parts = core.utils.split_uri(path, "/")
    local current = ""
    for _, part in ipairs(parts) do
        if part ~= "" then
            current = current .. "/" .. part
            local exists, err = client:exists(current)
            if err then
                core.log.error("check zk path exists failed: ", err)
                return false, err
            end
            if not exists then
                local ok, err = client:create(current, "", "persistent", false)
                if not ok and err ~= "node already exists" then
                    core.log.error("create zk path failed: ", current, " err: ", err)
                    return false, err
                end
            end
        end
    end
    return true
end

-- : Map ZK instance fields to APISIX
function _M.parse_instance_data(data)
    local instance = json.decode(data)
    if not instance then
        core.log.error("invalid instance data: ", data)
        return nil
    end

    -- Validate Required Fields
    if not instance.host or not instance.port then
        core.log.error("instance missing host/port: ", json.encode(instance))
        return nil
    end

    return {
        host = instance.host,
        port = tonumber(instance.port) or 80,
        weight = tonumber(instance.weight) or 100,
        metadata = instance.metadata
    }
end

-- Close ZK Clients
function _M.close_zk_client(client)
    if client then
        local ok, err = client:close()
        if not ok then
            core.log.error("close zk client failed: ", err)
        end
    end
end

return _M
