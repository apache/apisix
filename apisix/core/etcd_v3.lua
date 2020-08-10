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
local fetch_local_conf = require("apisix.core.config_local").local_conf
local etcd             = require("resty.etcd")
local clone_tab        = require("table.clone")
local type             = type
local string           = string
local tonumber         = tonumber

local _M = {version = 0.1}

local function new()
    local local_conf, err = fetch_local_conf()
    if not local_conf then
        return nil, nil, err
    end

    local etcd_conf = clone_tab(local_conf.etcd)
    local prefix = etcd_conf.prefix
    etcd_conf.http_host = etcd_conf.host
    etcd_conf.host = nil
    etcd_conf.prefix = nil
    etcd_conf.protocol = etcd_conf.version
    etcd_conf.version = nil
    etcd_conf.api_prefix = "/v3"

    local etcd_cli
    etcd_cli, err = etcd.new(etcd_conf)
    if not etcd_cli then
        return nil, nil, err
    end

    return etcd_cli, prefix
end
_M.new = new

local function kvs2node(kvs)
    local node = {}
    node.key = kvs.key
    node.value = kvs.value
    node.createdIndex = kvs.create_revision
    node.modifiedIndex = kvs.mod_revision
    return node
end

local function notfound(res)
    res.body.message = "Key not found"
    res.reason = "Not found"
    res.status = 404
    return res
end

function _M.postget(res, realkey)
    if res.body.error == "etcdserver: user name is empty" then
        return nil, "insufficient credentials code: 401"
    end

    res.headers["X-Etcd-Index"] = res.body.header.revision

    if not res.body.kvs then
        return notfound(res)
    end
    res.body.action = "get"

    local function kvs2nodes(res, start_index)
        res.body.node.dir = true
        res.body.node.nodes = {}
        for i=start_index, #res.body.kvs do
            res.body.node.nodes[i-1] = kvs2node(res.body.kvs[i])
        end
    end

    res.body.node = kvs2node(res.body.kvs[1])
    -- kvs.value = nil, so key is root
    if type(res.body.kvs[1].value) == "userdata" or not res.body.kvs[1].value then
        -- remove last "/" when necesary
        if string.sub(res.body.node.key, -1, -1) == "/" then
            res.body.node.key = string.sub(res.body.node.key, 1, #res.body.node.key-1)
        end
        kvs2nodes(res, 2)
    -- key not match, so realkey is root
    elseif res.body.kvs[1].key ~= realkey then
        res.body.node.key = realkey
        kvs2nodes(res, 1)
    -- first is root (in v2, root not contains value), others are nodes
    elseif #res.body.kvs > 1 then
        kvs2nodes(res, 2)
    end

    res.body.kvs = nil
    return res, nil
end

function _M.postwatch(v3res)
    local v2res = {}
    v2res.headers = {
        ["X-Etcd-Index"] = v3res.result.header.revision
    }
    v2res.body = {
        node = kvs2node(v3res.result.events[1].kv)
    }

    if v3res.result.events[1].type == "DELETE" then
        v2res.body.action = "delete"
    end

    return v2res
end


function _M.get(key)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    -- in etcd v2, get could implicitly turn into readdir
    -- while in v3, we need to do it explicitly
    local res, err = etcd_cli:readdir(prefix .. key)
    if not res then
        return nil, err
    end

    return _M.postget(res, prefix .. key)
end


local function set(key, value, ttl)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    -- lease substitute ttl in v3
    local res, err
    if ttl then
        local data, grant_err = etcd_cli:grant(tonumber(ttl))
        if not data then
            return nil, grant_err
        end
        res, err = etcd_cli:set(prefix .. key, value, {lease = data.body.ID})
    else
        res, err = etcd_cli:set(prefix .. key, value)
    end
    if not res then
        return nil, err
    end

    res.headers["X-Etcd-Index"] = res.body.header.revision

    -- etcd v3 set would not return kv info
    res.body.action = "set"
    res.body.node = {}
    res.body.node.key = prefix .. key
    res.body.node.value = value
    res.body.kvs = nil

    return res, nil
end
_M.set = set


function _M.push(key, value, ttl)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    local res, err = etcd_cli:readdir(prefix .. key)
    if not res then
        return nil, err
    end

    -- manually add suffix
    local index = res.body.header.revision
    index = string.format("%020d", index)

    res, err = set(key .. "/" .. index, value, ttl)
    if not res then
        return nil, err
    end

    res.body.action = "create"
    return res, nil
end


function _M.delete(key)
    local etcd_cli, prefix, err = new()
    if not etcd_cli then
        return nil, err
    end

    local res, err = etcd_cli:delete(prefix .. key)

    if not res then
        return nil, err
    end

    res.headers["X-Etcd-Index"] = res.body.header.revision

    if not res.body.deleted then
        return notfound(res), nil
    end

    -- etcd v3 set would not return kv info
    res.body.action = "delete"
    res.body.node = {}
    res.body.key = prefix .. key

    return res, nil
end


function _M.server_version()
    local etcd_cli, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:version()
end


return _M
