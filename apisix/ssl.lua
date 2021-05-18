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
local aes = require "resty.aes"
local assert = assert
local type = type


local cert_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}

local pkey_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}


local _M = {}


local _aes_128_cbc_with_iv = false
local function get_aes_128_cbc_with_iv()
    if _aes_128_cbc_with_iv == false then
        local local_conf = core.config.local_conf()
        local iv = core.table.try_read_attr(local_conf, "apisix", "ssl", "key_encrypt_salt")
        if type(iv) =="string" and #iv == 16 then
            _aes_128_cbc_with_iv = assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv = iv}))
        else
            _aes_128_cbc_with_iv = nil
        end
    end
    return _aes_128_cbc_with_iv
end


function _M.aes_encrypt_pkey(origin)
    local aes_128_cbc_with_iv = get_aes_128_cbc_with_iv()
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


local function decrypt_priv_pkey(iv, key)
    local decoded_key = ngx_decode_base64(key)
    if not decoded_key then
        core.log.error("base64 decode ssl key failed. key[", key, "] ")
        return nil
    end

    local decrypted = iv:decrypt(decoded_key)
    if not decrypted then
        core.log.error("decrypt ssl key failed. key[", key, "] ")
    end

    return decrypted
end


local function aes_decrypt_pkey(origin)
    if core.string.has_prefix(origin, "---") then
        return origin
    end

    local aes_128_cbc_with_iv = get_aes_128_cbc_with_iv()
    if aes_128_cbc_with_iv ~= nil then
        return decrypt_priv_pkey(aes_128_cbc_with_iv, origin)
    end
    return origin
end


local function validate(cert, key)
    local parsed_cert, err = ngx_ssl.parse_pem_cert(cert)
    if not parsed_cert then
        return nil, "failed to parse cert: " .. err
    end

    if key == nil then
        -- sometimes we only need to validate the cert
        return true
    end

    key = aes_decrypt_pkey(key)
    if not key then
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

    local parsed, err = ngx_ssl.parse_pem_priv_key(aes_decrypt_pkey(pkey))
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
