-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied.  See the License for the
-- specific language governing permissions and limitations
-- under the License.

-- local common libs
local require = require
local pcall = pcall
local ffi = require("ffi")
local C = ffi.C
local get_request = require("resty.core.base").get_request
local core = require("apisix.core")
local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
local apisix_ssl = require("apisix.ssl")
local _, ssl = pcall(require, "resty.apisix.ssl")
local error = error


ffi.cdef[[
unsigned long Tongsuo_version_num(void)
]]


-- local function
local function set_pem_ssl_key(sni, enc_cert, enc_pkey, sign_cert, sign_pkey)
    local r = get_request()
    if r == nil then
        return false, "no request found"
    end

    local parsed_enc_cert, err = apisix_ssl.fetch_cert(sni, enc_cert)
    if not parsed_enc_cert then
        return false, "failed to parse enc PEM cert: " .. err
    end

    local parsed_sign_cert, err = apisix_ssl.fetch_cert(sni, sign_cert)
    if not parsed_sign_cert then
        return false, "failed to parse sign PEM cert: " .. err
    end

    local ok, err = ssl.set_gm_cert(parsed_enc_cert, parsed_sign_cert)
    if not ok then
        return false, "failed to set PEM cert: " .. err
    end

    local parsed_enc_pkey, err = apisix_ssl.fetch_pkey(sni, enc_pkey)
    if not parsed_enc_pkey then
        return false, "failed to parse enc PEM priv key: " .. err
    end

    local parsed_sign_pkey, err = apisix_ssl.fetch_pkey(sni, sign_pkey)
    if not parsed_sign_pkey then
        return false, "failed to parse sign PEM priv key: " .. err
    end

    ok, err = ssl.set_gm_priv_key(parsed_enc_pkey, parsed_sign_pkey)
    if not ok then
        return false, "failed to set PEM priv key: " .. err
    end

    return true
end


local original_set_cert_and_key
local function set_cert_and_key(sni, value)
    if value.gm then
        -- process as GM certificate
        -- For GM dual certificate, the `cert` and `key` will be encryption cert/key.
        -- The first item in `certs` and `keys` will be sign cert/key.
        local enc_cert = value.cert
        local enc_pkey = value.key
        local sign_cert = value.certs[1]
        local sign_pkey = value.keys[1]
        return set_pem_ssl_key(sni, enc_cert, enc_pkey, sign_cert, sign_pkey)
    end
    return original_set_cert_and_key(sni, value)
end


local original_check_ssl_conf
local function check_ssl_conf(in_dp, conf)
    if conf.gm then
        -- process as GM certificate
        -- For GM dual certificate, the `cert` and `key` will be encryption cert/key.
        -- The first item in `certs` and `keys` will be sign cert/key.
        local ok, err = original_check_ssl_conf(in_dp, conf)
        -- check cert/key first in the original method
        if not ok then
            return nil, err
        end

        -- Currently, APISIX doesn't check the cert type (ECDSA / RSA). So we skip the
        -- check for now in this plugin.
        local num_certs = conf.certs and #conf.certs or 0
        local num_keys = conf.keys and #conf.keys or 0
        if num_certs ~= 1 or num_keys ~= 1 then
            return nil, "sign cert/key are required"
        end
        return true
    end
    return original_check_ssl_conf(in_dp, conf)
end


-- module define
local plugin_name = "gm"

-- plugin schema
local plugin_schema = {
    type = "object",
    properties = {
    },
}

local _M = {
    version  = 0.1,            -- plugin version
    priority = -43,
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}


function _M.init()
    if not pcall(function () return C.Tongsuo_version_num end) then
        error("need to build Tongsuo (https://github.com/Tongsuo-Project/Tongsuo) " ..
              "into the APISIX-Base")
    end

    ssl.enable_ntls()
    original_set_cert_and_key = radixtree_sni.set_cert_and_key
    radixtree_sni.set_cert_and_key = set_cert_and_key
    original_check_ssl_conf = apisix_ssl.check_ssl_conf
    apisix_ssl.check_ssl_conf = check_ssl_conf

    if core.schema.ssl.properties.gm ~= nil then
        error("Field 'gm' is occupied")
    end

    -- inject a mark to distinguish GM certificate
    core.schema.ssl.properties.gm = {
        type = "boolean"
    }
end


function _M.destroy()
    ssl.disable_ntls()
    radixtree_sni.set_cert_and_key = original_set_cert_and_key
    apisix_ssl.check_ssl_conf = original_check_ssl_conf
    core.schema.ssl.properties.gm = nil
end

-- module interface for schema check
-- @param `conf` user defined conf data
-- @param `schema_type` defined in `apisix/core/schema.lua`
-- @return <boolean>
function _M.check_schema(conf, schema_type)
    return core.schema.check(plugin_schema, conf)
end


return _M
