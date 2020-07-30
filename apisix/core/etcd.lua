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
local etcd = require("resty.etcd")
local clone_tab = require("table.clone")
local type = type
local string = string
local tostring = tostring
local tonumber = tonumber


local _M = {version = 0.2}

local function repeats(s, n) return n > 0 and s .. repeats(s, n-1) or "" end

local function new()
    local local_conf, err = fetch_local_conf()
    if not local_conf then
        return nil, nil, nil, err
    end

    local etcd_conf = clone_tab(local_conf.etcd)
    local prefix = etcd_conf.prefix
    etcd_conf.http_host = etcd_conf.host
    etcd_conf.host = nil
    etcd_conf.prefix = nil

    local etcd_cli
    if etcd_conf.protocol == nil then
        etcd_conf.protocol = "v2"
    end

    etcd_cli, err = etcd.new(etcd_conf)
    if not etcd_cli then
        return nil, nil, nil, err
    end

    return etcd_cli, prefix, etcd_conf.protocol
end
_M.new = new


function _M.get(key, opts)
    local etcd_cli, prefix, protocol, err = new()
    if not etcd_cli then
        return nil, err
    end

    key = prefix .. key
    local res, err
    if protocol == "v2" then
        res, err = etcd_cli:get(key, opts)
    else
        res, err = etcd_cli:readdir(key, opts)
        local rtrim_key = string.match(key, [[^(.-)/*$]])
        local etcd_obj = {
            node = {},
            action = "get"
        }

        local nodes_inx = 1
        local is_dir = false

        if type(res.body.kvs) == "table" and #res.body.kvs > 0  then
            for _, node in ipairs(res.body.kvs) do
                local node_key = string.gsub(node.key, key, "")
                node_key = string.match(node_key, [[^/*(.-)$]])
                if node.value == ngx.null or is_dir then
                    etcd_obj.node.createdIndex = node.create_revision
                    etcd_obj.node.modifiedIndex = node.mod_revision
                    etcd_obj.node.dir = true
                elseif node_key == ""  then
                    etcd_obj.node.createdIndex = node.create_revision
                    etcd_obj.node.modifiedIndex = node.mod_revision
                    etcd_obj.node.key = node.key
                    etcd_obj.node.value = node.value
                end

                if node_key ~= "" then
                    local sep_inx = string.find(node_key, "/")
                    if sep_inx then
                        node_key = string.sub(node_key, 1, sep_inx - 1)
                        etcd_obj.node.nodes = etcd_obj.node.nodes or {}
                        is_dir = true

                        etcd_obj.node.nodes[nodes_inx] =  {
                            key = rtrim_key .. "/" .. node_key,
                            modifiedIndex = node.mod_revision,
                            createdIndex = node.create_revision,
                            dir = true
                        }
                    else
                        etcd_obj.node.nodes = etcd_obj.node.nodes or {}
                        etcd_obj.node.nodes[nodes_inx] =  {
                            key = rtrim_key .. "/" .. node_key,
                            modifiedIndex = node.mod_revision,
                            createdIndex = node.create_revision,
                            value = node.value
                        }
                    end
                    nodes_inx = nodes_inx + 1
                end
            end
        else
            etcd_obj = {
                cause = key,
                index = res.body.header.revision,
                errorCode = 100,
                message = "Key not found"
            }
        end
        res.body = etcd_obj
    end

    return res, err
end


function _M.set(key, value, ttl, opts)
    local etcd_cli, prefix, protocol, err = new()
    if not etcd_cli then
        return nil, err
    end

    key = prefix .. key
    local res, err = etcd_cli:set(key, value, ttl, opts)

    if protocol == "v3" and not err and res.status == 200 then
        local node
        if type(res.body.header) == "table" and #res.body.header > 0  then
            node = {
                key = key,
                value = value,
                modifiedIndex = res.body.header.revision,
                createdIndex = res.body.header.revision,
            }
        end
        local etcd_obj = {
            node = node,
            action = "set"
        }
        res.body = etcd_obj
    end

    return res, err
end


function _M.push(key, value, ttl, opts)
    local etcd_cli, prefix, protocol, err = new()
    if not etcd_cli then
        return nil, err
    end

    local res, err
    if protocol == "v2" then
        res, err = etcd_cli:push(prefix .. key, value, ttl, opts)
    else
        local last_id = 0
        local max_id_len = 20
        res, err = etcd_cli:readdir(prefix .. key, {count_only=true})
        if err ~= nil then
            return nil, err
        end

        if res.body and res.body.header.revision then
            last_id = tonumber(res.body.header.revision) + 1
        end

        if last_id > 0 then
            local last_id_len = string.len(tostring(last_id))
            key =  key .. "/" .. repeats("0", max_id_len - last_id_len) .. last_id
            res, err = etcd_cli:set(prefix .. key, value, ttl, opts)
            res.body = {
                node = {
                    key = prefix .. key,
                    value = value,
                    modifiedIndex = res.body.header.revision,
                    createdIndex = res.body.header.revision,
                },
                action = "create"
            }
        else
            return nil, "push etcd mistake"
        end
    end
    return res, err
end


function _M.delete(key)
    local etcd_cli, prefix, protocol, err = new()
    if not etcd_cli then
        return nil, err
    end

    local res, err = etcd_cli:delete(prefix .. key)
    if protocol == "v3" and res.body then
        res.body = {
            key = prefix .. key,
            modifiedIndex = res.body.header.revision,
            createdIndex = res.body.header.revision,
        }
    end
    return res, err
end


function _M.server_version(key)
    local etcd_cli, err = new()
    if not etcd_cli then
        return nil, err
    end

    return etcd_cli:version()
end


return _M
