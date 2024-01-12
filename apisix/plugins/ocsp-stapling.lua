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
local ngx_ctx = require("ngx.ctx")
local ngx_ocsp = require("ngx.ocsp")
local ngx_ssl = require("ngx.ssl")
local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
local core = require("apisix.core")
local apisix_ssl = require("apisix.ssl")

local cache_ttl = 3600
local plugin_name = "ocsp-stapling"
local ocsp_resp_cache = ngx.shared[plugin_name]

local plugin_schema = {
    type = "object",
    properties = {},
}

local _M = {
    name = plugin_name,
    schema = plugin_schema,
    version = 0.1,
    priority = -44,
}


function _M.check_schema(conf)
    return core.schema.check(plugin_schema, conf)
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


local function get_remote_ocsp_resp(der_cert_chain)
    core.log.debug("get remote ocsp resp ... ")
    local ocsp_url, err = ngx_ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)
    -- if cert not support ocsp, the report error is nil
    if not err then
        err = "cert not cotains authority_information_access extension"
    end

    if not ocsp_url then
        return nil, "failed to get ocsp url: " .. err
    end

    local ocsp_req, err = ngx_ocsp.create_ocsp_request(der_cert_chain)
    if not ocsp_req then
        return nil, "failed to create ocsp request: " .. err
    end

    local httpc = http.new()
    local res, err = httpc:request_uri(ocsp_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/ocsp-request",
        },
        body = ocsp_req
    })

    if not res then
        return nil, "ocsp responder query failed: " .. err
    end

    local http_status = res.status
    if http_status ~= 200 then
        return nil, "ocsp responder returns bad http status code: "
               .. http_status
    end

    if res.body and #res.body > 0 then
        return res.body, nil
    end

    return nil, "ocsp responder returns empty body"
end


local function set_ocsp_resp(full_chain_pem_cert)
    local der_cert_chain, err = ngx_ssl.cert_pem_to_der(full_chain_pem_cert)
    if not der_cert_chain then
        return false, "failed to convert certificate chain from PEM to DER: ", err
    end

    local ocsp_resp = ocsp_resp_cache:get(full_chain_pem_cert)
    local resp_from_cache = true
    if ocsp_resp == nil then
        core.log.debug("not ocsp resp cache found, fetch from ocsp responder")
        resp_from_cache = false
        ocsp_resp, err = get_remote_ocsp_resp(der_cert_chain)
    end

    if ocsp_resp == nil then
        return false, err
    end

    local ok, err = ngx_ocsp.validate_ocsp_response(ocsp_resp, der_cert_chain)
    if not ok then
        -- try delete cache
        if resp_from_cache then
            ocsp_resp_cache:delete(full_chain_pem_cert)
        end
        return false, "failed to validate ocsp response: " .. err
    end
    ocsp_resp_cache:set(full_chain_pem_cert, ocsp_resp, cache_ttl)

    -- set the OCSP stapling
    ok, err = ngx_ocsp.set_ocsp_status_resp(ocsp_resp)
    if not ok or err ~= nil then
        return false, "failed to set ocsp status response: " .. err
    end

    return true
end


local original_set_cert_and_key
local function set_cert_and_key(sni, value)
    if value.gm then
        -- should not run with gm plugin
        core.log.info("gm plugin enabled, no need to run ocsp-stapling plugin")
        return original_set_cert_and_key(sni, value)
    end

    if value.ocsp_stapling then
        if not ngx_ctx.tls_ext_status_req then
            core.log.info("no status request required, no need to send ocsp response")
            return original_set_cert_and_key(sni, value)
        end

        local ok, err = set_pem_ssl_key(sni, value.cert, value.key)
        if not ok then
            return false, err
        end
        local fin_pem_cert = value.cert

        -- multiple certificates support.
        if value.certs then
            for i = 1, #value.certs do
                local cert = value.certs[i]
                local key = value.keys[i]
                ok, err = set_pem_ssl_key(sni, cert, key)
                if not ok then
                    return false, err
                end
                fin_pem_cert = cert
            end
        end

        local ok, err = set_ocsp_resp(fin_pem_cert)
        if not ok then
            core.log.error("no ocsp response send: ", err)
        end

        return true
    end
end


function _M.init()
    if core.schema.ssl.properties.gm ~= nil then
        core.log.error("ocsp-stapling plugin should not run with gm plugin")
    end

    original_set_cert_and_key = radixtree_sni.set_cert_and_key
    radixtree_sni.set_cert_and_key = set_cert_and_key

    if core.schema.ssl.properties.ocsp_stapling ~= nil then
        core.log.error("Field 'ocsp_stapling' is occupied")
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
