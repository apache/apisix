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
local core              = require("apisix.core")
local tostring          = tostring
local aes               = require "resty.aes"
local ngx_encode_base64 = ngx.encode_base64
local type              = type
local assert            = assert

local _M = {
    version = 0.1,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing ssl id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong ssl id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong ssl id"}
    end

    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(core.schema.ssl))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.ssl, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local numcerts = conf.certs and #conf.certs or 0
    local numkeys = conf.keys and #conf.keys or 0
    if numcerts ~= numkeys then
        return nil, {error_msg = "mismatched number of certs and keys"}
    end

    return need_id and id or true
end


local function aes_encrypt(origin)
    local local_conf = core.config.local_conf()
    local iv
    if local_conf and local_conf.apisix
       and local_conf.apisix.ssl.key_encrypt_salt then
        iv = local_conf.apisix.ssl.key_encrypt_salt
    end
    local aes_128_cbc_with_iv = (type(iv)=="string" and #iv == 16) and
            assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv=iv})) or nil

    if aes_128_cbc_with_iv ~= nil and core.string.has_prefix(origin, "---") then
        local encrypted = aes_128_cbc_with_iv:encrypt(origin)
        if encrypted == nil then
            core.log.error("failed to encrypt key[", origin, "] ")
            return origin
        end

        return ngx_encode_base64(encrypted)
    end

    return origin
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    -- encrypt private key
    conf.key = aes_encrypt(conf.key)

    if conf.keys then
        for i = 1, #conf.keys do
            conf.keys[i] = aes_encrypt(conf.keys[i])
        end
    end

    local key = "/ssl/" .. id
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put ssl[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/ssl"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get ssl[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    -- not return private key for security
    if res.body and res.body.node and res.body.node.value then
        res.body.node.value.key = nil
    end

    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    -- encrypt private key
    conf.key = aes_encrypt(conf.key)

    if conf.keys then
        for i = 1, #conf.keys do
            conf.keys[i] = aes_encrypt(conf.keys[i])
        end
    end

    local key = "/ssl"
    -- core.log.info("key: ", key)
    local res, err = core.etcd.push("/ssl", conf)
    if not res then
        core.log.error("failed to post ssl[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing ssl id"}
    end

    local key = "/ssl/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete ssl[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(id, conf)
    if not id then
        return 400, {error_msg = "missing route id"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    if type(conf) ~= "table"  then
        return 400, {error_msg = "invalid configuration"}
    end

    local key = "/ssl"
    if id then
        key = key .. "/" .. id
    end

    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get ssl [", key, "] in etcd: ", err)
        return 500, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
                  core.json.delay_encode(res_old, true))


    local node_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    node_value = core.table.merge(node_value, conf);

    core.log.info("new ssl conf: ", core.json.delay_encode(node_value, true))

    local id, err = check_conf(id, node_value, true)
    if not id then
        return 400, err
    end

    local res, err = core.etcd.atomic_set(key, node_value, nil, modified_index)
    if not res then
        core.log.error("failed to set new ssl[", key, "] to etcd: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
