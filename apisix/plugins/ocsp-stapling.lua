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
local get_request = require("resty.core.base").get_request
local http = require("resty.http")
local ngx = ngx
local ngx_ocsp = require("ngx.ocsp")
local ngx_ssl = require("ngx.ssl")
local radixtree_sni = require("apisix.ssl.router.radixtree_sni")
local core = require("apisix.core")
local apisix_ssl = require("apisix.ssl")

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


local function fetch_ocsp_resp(der_cert_chain)
    core.log.info("fetch ocsp response from remote")
    local ocsp_url, err = ngx_ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)

    if not ocsp_url then
        -- if cert not support ocsp, the report error is nil
        if not err then
            err = "cert not contains authority_information_access extension"
        end
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


local function set_ocsp_resp(full_chain_pem_cert, skip_verify, cache_ttl)
    local der_cert_chain, err = ngx_ssl.cert_pem_to_der(full_chain_pem_cert)
    if not der_cert_chain then
        return false, "failed to convert certificate chain from PEM to DER: ", err
    end

    local ocsp_resp = ocsp_resp_cache:get(der_cert_chain)
    if ocsp_resp == nil then
        core.log.info("not ocsp resp cache found, fetch from ocsp responder")
        ocsp_resp, err = fetch_ocsp_resp(der_cert_chain)
        if ocsp_resp == nil then
            return false, err
        end
        core.log.info("fetch ocsp resp ok, cache it")
        ocsp_resp_cache:set(der_cert_chain, ocsp_resp, cache_ttl)
    end

    if not skip_verify then
        local ok, err = ngx_ocsp.validate_ocsp_response(ocsp_resp, der_cert_chain)
        if not ok then
            return false, "failed to validate ocsp response: " .. err
        end
    end

    -- set the OCSP stapling
    local ok, err = ngx_ocsp.set_ocsp_status_resp(ocsp_resp)
    if not ok then
        return false, "failed to set ocsp status response: " .. err
    end

    return true
end


local original_set_cert_and_key
local function set_cert_and_key(sni, value)
    if value.gm then
        -- should not run with gm plugin
        core.log.warn("gm plugin enabled, no need to run ocsp-stapling plugin")
        return original_set_cert_and_key(sni, value)
    end

    if not value.ocsp_stapling then
        core.log.info("no 'ocsp_stapling' field found, no need to run ocsp-stapling plugin")
        return original_set_cert_and_key(sni, value)
    end

    if not value.ocsp_stapling.enabled then
        return original_set_cert_and_key(sni, value)
    end

    if not ngx.ctx.tls_ext_status_req then
        core.log.info("no status request required, no need to send ocsp response")
        return original_set_cert_and_key(sni, value)
    end

    local ok, err = radixtree_sni.set_pem_ssl_key(sni, value.cert, value.key)
    if not ok then
        return false, err
    end
    local fin_pem_cert = value.cert

    -- multiple certificates support.
    if value.certs then
        for i = 1, #value.certs do
            local cert = value.certs[i]
            local key = value.keys[i]
            ok, err = radixtree_sni.set_pem_ssl_key(sni, cert, key)
            if not ok then
                return false, err
            end
            fin_pem_cert = cert
        end
    end

    local ok, err = set_ocsp_resp(fin_pem_cert,
                                  value.ocsp_stapling.skip_verify,
                                  value.ocsp_stapling.cache_ttl)
    if not ok then
        core.log.error("no ocsp response send: ", err)
    end

    return true
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
        type = "object",
        properties = {
            enabled = {
                type = "boolean",
                default = false,
            },
            skip_verify = {
                type = "boolean",
                default = false,
            },
            cache_ttl = {
                type = "integer",
                minimum = 60,
                default = 3600,
            },
        }
    }

end


function _M.destroy()
    radixtree_sni.set_cert_and_key = original_set_cert_and_key
    core.schema.ssl.properties.ocsp_stapling = nil
    ocsp_resp_cache:flush_all()
end


return _M
