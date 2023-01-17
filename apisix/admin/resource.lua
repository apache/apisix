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
local tostring = tostring
local type = type


local _M = {
    need_v3_filter = true,
}


local mt = {
    __index = _M
}


function _M:check_conf(id, conf, need_id)
    -- check if missing configurations
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    -- check id if need id
    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing ".. self.kind .. " id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong ".. self.kind .. " id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong ".. self.kind .. " id"}
    end

    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(self.schema))
    core.log.info("conf  : ", core.json.delay_encode(conf))

    -- check the resource own rules
    local ok, err = self.checker(id, conf, need_id, self.schema)

    if not ok then
        return ok, err
    else
        return need_id and id or true
    end
end


function _M:get(id)
    if core.table.array_find(self.unsupported_methods, "get") then
        return 405, {error_msg = "not supported `GET` method for " .. self.kind}
    end

    local key = "/" .. self.name
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get ", self.kind, "[", key, "] from etcd: ", err)
        return 503, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


function _M:post(id, conf, sub_path, args)
    if core.table.array_find(self.unsupported_methods, "post") then
        return 405, {error_msg = "not supported `POST` method for " .. self.kind}
    end

    local id, err = self:check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/" .. self.name
    utils.inject_timestamp(conf)

    local ttl = nil
    if args then
        ttl = args.ttl
    end

    local res, err = core.etcd.push(key, conf, ttl)
    if not res then
        core.log.error("failed to post ", self.kind, "[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M:put(id, conf, sub_path, args)
    if core.table.array_find(self.unsupported_methods, "put") then
        return 405, {error_msg = "not supported `PUT` method for " .. self.kind}
    end

    local id, err = self:check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/" .. self.name .. "/" .. id

    local ok, err = utils.inject_conf_with_prev_conf(self.kind, key, conf)
    if not ok then
        return 503, {error_msg = err}
    end

    local ttl = nil
    if args then
        ttl = args.ttl
    end

    local res, err = core.etcd.set(key, conf, ttl)
    if not res then
        core.log.error("failed to put ", self.kind, "[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M:delete(id)
    if core.table.array_find(self.unsupported_methods, "delete") then
        return 405, {error_msg = "not supported `DELETE` method for " .. self.kind}
    end

    if not id then
        return 400, {error_msg = "missing " .. self.kind .. " id"}
    end

    if self.delete_checker then
        local code, err = self.delete_checker(id)
        if err then
            return code, err
        end
    end

    local key = "/" .. self.name .. "/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete ", self.kind, "[", key, "] in etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M:patch(id, conf, sub_path, args)
    if core.table.array_find(self.unsupported_methods, "patch") then
        return 405, {error_msg = "not supported `PATCH` method for " .. self.kind}
    end

    if not id then
        return 400, {error_msg = "missing " .. self.kind .. " id"}
    end

    if conf == nil then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/" .. self.name
    if id then
        key = key .. "/" .. id
    end

    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get ", self.kind, " [", key, "] in etcd: ", err)
        return 503, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ", core.json.delay_encode(res_old, true))

    local node_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    if sub_path and sub_path ~= "" then
        local code, err, node_val = core.table.patch(node_value, sub_path, conf)
        node_value = node_val
        if code then
            return code, {error_msg = err}
        end
        utils.inject_timestamp(node_value, nil, true)
    else
        node_value = core.table.merge(node_value, conf)
        utils.inject_timestamp(node_value, nil, conf)
    end

    core.log.info("new conf: ", core.json.delay_encode(node_value, true))

    local id, err = self:check_conf(id, node_value, true)
    if not id then
        return 400, err
    end

    local ttl = nil
    if args then
        ttl = args.ttl
    end

    local res, err = core.etcd.atomic_set(key, node_value, ttl, modified_index)
    if not res then
        core.log.error("failed to set new ", self.kind, "[", key, "] to etcd: ", err)
        return 503, {error_msg = err}
    end

    return res.status, res.body
end


function _M.new(opt)
    return setmetatable(opt, mt)
end


return _M
