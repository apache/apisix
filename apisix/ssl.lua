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
local core           = require("apisix.core")
local secret         = require("apisix.secret")
local data_encryption = core.data_encryption
local ngx_ssl        = require("ngx.ssl")
local ngx_ssl_client = require("ngx.ssl.clienthello")

local str_lower = string.lower
local str_byte = string.byte
local ngx_sub = ngx.re.sub

local cert_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}

local pkey_cache = core.lrucache.new {
    ttl = 3600, count = 1024,
}


local _M = {}


function _M.server_name(clienthello)
    local sni, err
    if clienthello then
        sni, err = ngx_ssl_client.get_client_hello_server_name()
    else
        sni, err = ngx_ssl.server_name()
    end
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

    sni = ngx_sub(sni, "\\.$", "", "jo")
    sni = str_lower(sni)
    return sni
end


function _M.session_hostname()
    return ngx_ssl.session_hostname()
end


function _M.set_protocols_by_clienthello(ssl_protocols)
    if ssl_protocols then
       return ngx_ssl_client.set_protocols(ssl_protocols)
    end
    return true
end


-- Encrypt an SSL private key with the data_encryption keyring. Only PEM-form
-- keys are encrypted, so already-encrypted or non-PEM values pass through.
function _M.aes_encrypt_pkey(origin)
    if not core.string.has_prefix(origin, "---") then
        return origin
    end

    return data_encryption.encrypt(origin)
end


local function aes_decrypt_pkey(origin)
    if core.string.has_prefix(origin, "---") then
        return origin
    end

    return data_encryption.decrypt(origin, "ssl key")
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

    if not secret.check_secret_uri(conf.cert) and
        not secret.check_secret_uri(conf.key) then

        local ok, err = validate(conf.cert, conf.key)
        if not ok then
            return nil, err
        end
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
        if not secret.check_secret_uri(conf.certs[i]) and
            not secret.check_secret_uri(conf.keys[i]) then

            local ok, err = validate(conf.certs[i], conf.keys[i])
            if not ok then
                return nil, "failed to handle cert-key pair[" .. i .. "]: " .. err
            end
        end
    end

    if conf.client then
        if not support_client_verification() then
            return nil, "client tls verify unsupported"
        end

        if not secret.check_secret_uri(conf.client.ca) then
            local ok, err = validate(conf.client.ca, nil)
            if not ok then
                return nil, "failed to validate client_cert: " .. err
            end
        end
    end

    return true
end


function _M.get_status_request_ext()
    core.log.debug("parsing status request extension ... ")
    local ext = ngx_ssl_client.get_client_hello_ext(5)
    if not ext then
        core.log.debug("no contains status request extension")
        return false
    end
    local total_len = #ext
    -- 1-byte for CertificateStatusType
    -- 2-byte for zero-length "responder_id_list"
    -- 2-byte for zero-length "request_extensions"
    if total_len < 5 then
        core.log.error("bad ssl client hello extension: ",
                       "extension data error")
        return false
    end

    -- CertificateStatusType
    local status_type = str_byte(ext, 1)
    if status_type == 1 then
        core.log.debug("parsing status request extension ok: ",
                       "status_type is ocsp(1)")
        return true
    end

    return false
end


return _M
