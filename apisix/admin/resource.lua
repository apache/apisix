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
    kind = "",
    version = 0.2,
    need_v3_filter = true,
}


local mt = {
    __index = _M,
    __tostring = function(self)
        return "resource name: " .. (_M.name)
    end
}


function _M.new(name, kind)
    return setmetatable({
        name = name,
        kind = kind
    }, mt)
end


function _M.get(id)
    local key = "/" .. _M.name
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get " .. _M.kind .. "[", key, "] from etcd: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


function _M.post(check_conf, id, conf, sub_path, args)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/" .. _M.name
    utils.inject_timestamp(conf)
    local res, err = core.etcd.push(key, conf, args.ttl)
    if not res then
        core.log.error("failed to post " .. _M.kind .. "[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.put(check_conf, id, conf, sub_path, args)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/" .. _M.name .. "/" .. id

    local ok, err = utils.inject_conf_with_prev_conf(_M.kind, key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf, args.ttl)
    if not res then
        core.log.error("failed to put " .. _M.kind .. "[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing " .. _M.kind .. " id"}
    end

    local key = "/" .. _M.name .. "/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete " .. _M.kind .. "[", key, "] in etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(check_conf, id, conf, sub_path, args)
    if not id then
        return 400, {error_msg = "missing " .. _M.kind .. " id"}
    end

    if conf == nil then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/" .. _M.name
    if id then
        key = key .. "/" .. id
    end

    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get " .. _M.kind .. " [", key, "] in etcd: ", err)
        return 503, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
            core.json.delay_encode(res_old, true))

    local node_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    if sub_path and sub_path ~= "" then
        local code, err, node_val = core.table.patch(node_value, sub_path, conf)
        node_value = node_val
        if code then
            return code, err
        end
        utils.inject_timestamp(node_value, nil, true)
    else
        node_value = core.table.merge(node_value, conf)
        utils.inject_timestamp(node_value, nil, conf)
    end

    core.log.info("new conf: ", core.json.delay_encode(node_value, true))

    local id, err = check_conf(id, node_value, true)
    if not id then
        return 400, err
    end

    local res, err = core.etcd.atomic_set(key, node_value, args.ttl, modified_index)
    if not res then
        core.log.error("failed to set new ".. _M.kind .."[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


return _M
