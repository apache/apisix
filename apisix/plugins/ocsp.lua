--
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
--

local require = require
local http = require("resty.http")
local radixtree_sni = require("apisix.ssl.router.radixtree_sni")


local pcall = pcall

local get_request = require("resty.core.base").get_request
local core = require("apisix.core")

local apisix_ssl = require("apisix.ssl")
local _, ssl = pcall(require, "resty.apisix.ssl")
local error = error
local plugin_name = "gm"


local plugin_schema = {
    type = "object",
    properties = {},
}

local _M = {
    version  = 0.1,            -- plugin version
    priority = -43,
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(plugin_schema, conf)
end


local function get_ocsp_resp(ocsp_url, ocsp_req)
    local httpc = http.new()
    local res, err = httpc:request_uri(ocsp_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/ocsp-request",
        },
        body = ocsp_req
    })

    if not res then
        core.log.error("OCSP responder query failed:", err, ", url:", ocsp_url)
        return
    end

    local http_status = res.status
    if http_status ~= 200 then
        core.log.error("OCSP responder returns bad HTTP status code:",
                       http_status, ", url:", ocsp_url)
        return
    end

    return res.body
end


local function set_pem_ssl_key(sni, cert, pkey)
    local r = get_request()
    if r == nil then
        return false, "no request found"
    end

    local parsed_cert, err = apisix_ssl.fetch_cert(sni, cert)
    if not parsed_cert then
        return false, "failed to parse PEM cert: " .. err
    end

    local ok, err = ngx_ssl.set_cert(parsed_cert)
    if not ok then
        return false, "failed to set PEM cert: " .. err
    end

    local parsed_pkey, err = apisix_ssl.fetch_pkey(sni, pkey)
    if not parsed_pkey then
        return false, "failed to parse PEM priv key: " .. err
    end

    ok, err = ngx_ssl.set_priv_key(parsed_pkey)
    if not ok then
        return false, "failed to set PEM priv key: " .. err
    end

    return true

    local ocsp = require "ngx.ocsp"
    local der_cert_chain, err = ngx_ssl.cert_pem_to_der(new_ssl_value.cert)
    if not der_cert_chain then
        core.log.error("failed to convert certificate chain ",
                       "from PEM to DER: ", err)
    end
    local ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)
    if not ocsp_url then
        core.log.error("failed to get OCSP url:", err)
    end

    local ocsp_req, err = ocsp.create_ocsp_request(der_cert_chain)
    if not ocsp_req then
        core.log.error("failed to create OCSP request:", err)
    end

    local ocsp_resp = get_ocsp_resp(ocsp_url, ocsp_req)
    if ocsp_resp and #ocsp_resp > 0 then
        local ok, err = ocsp.validate_ocsp_response(ocsp_resp, der_cert_chain)
        if not ok then
            core.log.error("failed to validate OCSP response: ", err)
        end
        -- set the OCSP stapling
        ok, err = ocsp.set_ocsp_status_resp(ocsp_resp)
        if not ok then
            core.log.error("failed to set ocsp status resp: ", err)
        end
    end


    return true
end


local original_set_cert_and_key
local function set_cert_and_key(sni, value)
    if value.gm then
        local ok, err = set_pem_ssl_key(sni, value.cert, value.key)
        if not ok then
            return false, err
        end
    
        -- multiple certificates support.
        if value.certs then
            for i = 1, #value.certs do
                local cert = value.certs[i]
                local key = value.keys[i]
    
                ok, err = set_pem_ssl_key(sni, cert, key)
                if not ok then
                    return false, err
                end
            end
        end
    
        return true
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


function _M.init()
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
    radixtree_sni.set_cert_and_key = original_set_cert_and_key
    apisix_ssl.check_ssl_conf = original_check_ssl_conf
    core.schema.ssl.properties.gm = nil
end



return _M
