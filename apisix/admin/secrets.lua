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

local core = require("apisix.core")
local utils = require("apisix.admin.utils")

local type = type
local tostring = tostring
local pcall = pcall


local _M = {
    need_v3_filter = true,
}


local function check_conf(id, conf, need_id, typ)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong id"}
    end

    conf.id = id

    core.log.info("conf: ", core.json.delay_encode(conf))
    local ok, secret_manager = pcall(require, "apisix.secret." .. typ)
    if not ok then
        return false, {error_msg = "invalid secret manager: " .. typ}
    end

    local ok, err = core.schema.check(secret_manager.schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return true
end


local function split_typ_and_id(id, sub_path)
    local uri_segs = core.utils.split_uri(sub_path)
    local typ = id
    local id = nil
    if #uri_segs > 0 then
        id = uri_segs[1]
    end
    return typ, id
end


function _M.put(id, conf, sub_path)
    local typ, id = split_typ_and_id(id, sub_path)
    if not id then
        return 400, {error_msg = "no secret id in uri"}
    end

    local ok, err = check_conf(typ .. "/" .. id, conf, true, typ)
    if not ok then
        return 400, err
    end

    local key = "/secrets/" .. typ .. "/" .. id

    local ok, err = utils.inject_conf_with_prev_conf("secrets", key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put secret [", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id, conf, sub_path)
    local typ, id = split_typ_and_id(id, sub_path)

    local key = "/secrets/"
    if id then
        key = key .. typ
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get secret [", key, "]: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


function _M.delete(id, conf, sub_path)
    local typ, id = split_typ_and_id(id, sub_path)
    if not id then
        return 400, {error_msg = "no secret id in uri"}
    end

    local key = "/secrets/" .. typ .. "/" .. id

    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete secret [", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(id, conf, sub_path)
    local uri_segs = core.utils.split_uri(sub_path)
    if #uri_segs < 2 then
        return 400, {error_msg = "no secret id and/or sub path in uri"}
    end
    local typ = id
    id = uri_segs[1]
    sub_path = core.table.concat(uri_segs, "/", 2)

    if not id then
        return 400, {error_msg = "missing secret id"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/secrets/" .. typ .. "/" .. id
    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get secret [", key, "]: ", err)
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

    local ok, err = check_conf(typ .. "/" .. id, node_value, true, typ)
    if not ok then
        return 400, {error_msg = err}
    end

    local res, err = core.etcd.atomic_set(key, node_value, nil, modified_index)
    if not res then
        core.log.error("failed to set new secret[", key, "]: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


return _M
