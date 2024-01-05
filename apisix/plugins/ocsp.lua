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
local pcall = pcall
local get_request = require("resty.core.base").get_request
local http = require("resty.http")
local ngx_ocsp = require("ngx.ocsp")
local ngx_ssl = require("ngx.ssl")
local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
local core = require("apisix.core")
local apisix_ssl = require("apisix.ssl")
local _, ssl = pcall(require, "resty.apisix.ssl")
local error = error


local plugin_name = "ocsp"

local plugin_schema = {
    type = "object",
    properties = {},
}

local _M = {
    version  = 0.1,
    priority = -42,
    name     = plugin_name,
    schema   = plugin_schema,
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
        return false, "OCSP responder query failed: " .. err
    end

    local http_status = res.status
    if http_status ~= 200 then
        return false, "OCSP responder returns bad HTTP status code: " .. http_status
    end

    return true, nil, res.body
end


local function get_ocsp_url_and_ocsp_req(pem_cert_chain)
    local der_cert_chain, err = ngx_ssl.cert_pem_to_der(pem_cert_chain)
    if not der_cert_chain then
        return false, "failed to convert certificate chain from PEM to DER: " .. err
    end

    local ocsp_url, err = ngx_ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)
    if not ocsp_url then
        return false, "failed to get OCSP url: " .. err
    end

    local ocsp_req, err = ocsp.create_ocsp_request(der_cert_chain)
    if not ocsp_req then
        return false, "failed to create OCSP request: " .. err
    end

    return true, nil, ocsp_url, ocsp_req
end


local function validate_and_set_ocsp_resp(der_cert_chain, ocsp_resp)
    if ocsp_resp and #ocsp_resp > 0 then
        local ok, err = ngx_ocsp.validate_ocsp_response(ocsp_resp, der_cert_chain)
        if not ok then
            return false, "failed to validate OCSP response: " .. err
        end

        -- set the OCSP stapling
        ok, err = ngx_ocsp.set_ocsp_status_resp(ocsp_resp)
        if not ok then
            return false, "failed to set ocsp status resp: " .. err
        end
    end

    return true
end


-- same as function set_pem_ssl_key() from "apisix.ssl.router.radixtree_sni" 
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
end


local original_set_cert_and_key
local function set_cert_and_key(sni, value)
    -- maybe not run with gm
    if value.ocsp_stapling then
        local ok, err = set_pem_ssl_key(sni, value.cert, value.key)
        if not ok then
            return false, err
        end
        local fin_cert = value.cert

        -- multiple certificates support.
        if value.certs then
            for i = 1, #value.certs do
                local cert = value.certs[i]
                local key = value.keys[i]
    
                ok, err = set_pem_ssl_key(sni, cert, key)
                if not ok then
                    return false, err
                end
                fin_cert = cert
            end
        end

        local ok, err, ocsp_url, ocsp_req = get_ocsp_url_and_ocsp_req(fin_cert)
        if not ok then
            -- get ocsp url failed, maybe certificates not support
            core.log.error(err)
            return true
        end
        local ok, err, ocsp_resp = get_ocsp_resp(ocsp_url, ocsp_req)
        if not ok then
            -- get ocsp resp failed
            core.log.error(err)
            return true
        end
        ok, err = validate_and_set_ocsp_resp(ocsp_resp)
        if not ok then
            -- validate or set ocsp resp failed
            core.log.error(err)
            return true
        end

        return true
    end
    return original_set_cert_and_key(sni, value)
end


function _M.init()
    original_set_cert_and_key = radixtree_sni.set_cert_and_key
    radixtree_sni.set_cert_and_key = set_cert_and_key

    if core.schema.ssl.properties.ocsp_stapling ~= nil then
        error("Field 'ocsp_stapling' is occupied")
    end

    core.schema.ssl.properties.ocsp_stapling = {
        type = "boolean"
    }
end


function _M.destroy()
    radixtree_sni.set_cert_and_key = original_set_cert_and_key
    core.schema.ssl.properties.ocsp_stapling = nil
end


return _M
