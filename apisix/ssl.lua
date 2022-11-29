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
local ngx_ssl = require("ngx.ssl")
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local aes = require("resty.aes")
local str_lower = string.lower
local assert = assert
local type = type
local ipairs = ipairs


local cert_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}

local pkey_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}


local _M = {}


function _M.server_name()
    local sni, err = ngx_ssl.server_name()
    if err then
        return nil, err
    end

    if not sni then
        local local_conf = core.config.local_conf()
        sni = core.table.try_read_attr(local_conf, "apisix", "ssl", "fallback_sni")
        if not sni then
            return nil
        end
    end

    sni = str_lower(sni)
    return sni
end


local function init_iv_tbl(ivs)
    local _aes_128_cbc_with_iv_tbl = core.table.new(2, 0)
    local type_ivs = type(ivs)

    if type_ivs == "table" then
        for _, iv in ipairs(ivs) do
            local aes_with_iv = assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv = iv}))
            core.table.insert(_aes_128_cbc_with_iv_tbl, aes_with_iv)
        end
    elseif type_ivs == "string" then
        local aes_with_iv = assert(aes:new(ivs, nil, aes.cipher(128, "cbc"), {iv = ivs}))
        core.table.insert(_aes_128_cbc_with_iv_tbl, aes_with_iv)
    end

    return _aes_128_cbc_with_iv_tbl
end


local _aes_128_cbc_with_iv_tbl_ssl
local function get_aes_128_cbc_with_iv_ssl(local_conf)
    if _aes_128_cbc_with_iv_tbl_ssl == nil then
        local ivs = core.table.try_read_attr(local_conf, "apisix", "ssl", "key_encrypt_salt")
        _aes_128_cbc_with_iv_tbl_ssl = init_iv_tbl(ivs)
    end

    return _aes_128_cbc_with_iv_tbl_ssl
end


local _aes_128_cbc_with_iv_tbl_gde
local function get_aes_128_cbc_with_iv_gde(local_conf)
    if _aes_128_cbc_with_iv_tbl_gde == nil then
        local ivs = core.table.try_read_attr(local_conf, "apisix", "data_encryption", "keyring")
        _aes_128_cbc_with_iv_tbl_gde = init_iv_tbl(ivs)
    end

    return _aes_128_cbc_with_iv_tbl_gde
end



local function encrypt(aes_128_cbc_with_iv, origin)
    local encrypted = aes_128_cbc_with_iv:encrypt(origin)
    if encrypted == nil then
        core.log.error("failed to encrypt key[", origin, "] ")
        return origin
    end

    return ngx_encode_base64(encrypted)
end

function _M.aes_encrypt_pkey(origin, field)
    local local_conf = core.config.local_conf()

    if not field then
        -- default used by ssl
        local aes_128_cbc_with_iv_tbl_ssl = get_aes_128_cbc_with_iv_ssl(local_conf)
        local aes_128_cbc_with_iv_ssl = aes_128_cbc_with_iv_tbl_ssl[1]
        if aes_128_cbc_with_iv_ssl ~= nil and core.string.has_prefix(origin, "---") then
            return encrypt(aes_128_cbc_with_iv_ssl, origin)
        end
    else
        if field == "data_encrypt" then
            local aes_128_cbc_with_iv_tbl_gde = get_aes_128_cbc_with_iv_gde(local_conf)
            local aes_128_cbc_with_iv_gde = aes_128_cbc_with_iv_tbl_gde[1]
            if aes_128_cbc_with_iv_gde ~= nil then
                return encrypt(aes_128_cbc_with_iv_gde, origin)
            end
        end
    end

    return origin
end


local function aes_decrypt_pkey(origin, field)
    local local_conf = core.config.local_conf()
    local aes_128_cbc_with_iv_tbl

    if not field then
        if core.string.has_prefix(origin, "---") then
            return origin
        end
        aes_128_cbc_with_iv_tbl = get_aes_128_cbc_with_iv_ssl(local_conf)
    else
        if field == "data_encrypt" then
            aes_128_cbc_with_iv_tbl = get_aes_128_cbc_with_iv_gde(local_conf)
        end
    end

    if #aes_128_cbc_with_iv_tbl == 0 then
        return origin
    end

    local decoded_key = ngx_decode_base64(origin)
    if not decoded_key then
        core.log.error("base64 decode ssl key failed. key[", origin, "] ")
        return nil
    end

    for _, aes_128_cbc_with_iv in ipairs(aes_128_cbc_with_iv_tbl) do
        local decrypted = aes_128_cbc_with_iv:decrypt(decoded_key)
        if decrypted then
            return decrypted
        end
    end

    return nil, "decrypt ssl key failed"
end
_M.aes_decrypt_pkey = aes_decrypt_pkey


local function validate(cert, key)
    local parsed_cert, err = ngx_ssl.parse_pem_cert(cert)
    if not parsed_cert then
        return nil, "failed to parse cert: " .. err
    end

    if key == nil then
        -- sometimes we only need to validate the cert
        return true
    end

    local err
    key, err = aes_decrypt_pkey(key)
    if not key then
        core.log.error(err)
        return nil, "failed to decrypt previous encrypted key"
    end

    local parsed_key, err = ngx_ssl.parse_pem_priv_key(key)
    if not parsed_key then
        return nil, "failed to parse key: " .. err
    end

    -- TODO: check if key & cert match
    return true
end
_M.validate = validate


local function parse_pem_cert(sni, cert)
    core.log.debug("parsing cert for sni: ", sni)

    local parsed, err = ngx_ssl.parse_pem_cert(cert)
    return parsed, err
end


function _M.fetch_cert(sni, cert)
    local parsed_cert, err = cert_cache(cert, nil, parse_pem_cert, sni, cert)
    if not parsed_cert then
        return false, err
    end

    return parsed_cert
end


local function parse_pem_priv_key(sni, pkey)
    core.log.debug("parsing priv key for sni: ", sni)

    local key, err = aes_decrypt_pkey(pkey)
    if not key then
        core.log.error(err)
        return nil, err
    end
    local parsed, err = ngx_ssl.parse_pem_priv_key(key)
    return parsed, err
end


function _M.fetch_pkey(sni, pkey)
    local parsed_pkey, err = pkey_cache(pkey, nil, parse_pem_priv_key, sni, pkey)
    if not parsed_pkey then
        return false, err
    end

    return parsed_pkey
end


local function support_client_verification()
    return ngx_ssl.verify_client ~= nil
end
_M.support_client_verification = support_client_verification


function _M.check_ssl_conf(in_dp, conf)
    if not in_dp then
        local ok, err = core.schema.check(core.schema.ssl, conf)
        if not ok then
            return nil, "invalid configuration: " .. err
        end
    end

    local ok, err = validate(conf.cert, conf.key)
    if not ok then
        return nil, err
    end

    if conf.type == "client" then
        return true
    end

    local numcerts = conf.certs and #conf.certs or 0
    local numkeys = conf.keys and #conf.keys or 0
    if numcerts ~= numkeys then
        return nil, "mismatched number of certs and keys"
    end

    for i = 1, numcerts do
        local ok, err = validate(conf.certs[i], conf.keys[i])
        if not ok then
            return nil, "failed to handle cert-key pair[" .. i .. "]: " .. err
        end
    end

    if conf.client then
        if not support_client_verification() then
            return nil, "client tls verify unsupported"
        end

        local ok, err = validate(conf.client.ca, nil)
        if not ok then
            return nil, "failed to validate client_cert: " .. err
        end
    end

    return true
end


return _M
