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
local get_request      = require("resty.core.base").get_request
local radixtree_new    = require("resty.radixtree").new
local core             = require("apisix.core")
local ngx_ssl          = require("ngx.ssl")
local ipairs           = ipairs
local type             = type
local error            = error
local str_find         = string.find
local aes              = require "resty.aes"
local assert           = assert
local ngx_decode_base64 = ngx.decode_base64
local ssl_certificates
local radixtree_router
local radixtree_router_ver


local _M = {
    version = 0.1,
    server_name = ngx_ssl.server_name,
}


local function create_router(ssl_items)
    local ssl_items = ssl_items or {}

    local route_items = core.table.new(#ssl_items, 0)
    local idx = 0

    local local_conf = core.config.local_conf()
    local iv
    if local_conf and local_conf.apisix
       and local_conf.apisix.ssl
       and local_conf.apisix.ssl.key_encrypt_salt then
        iv = local_conf.apisix.ssl.key_encrypt_salt
    end
    local aes_128_cbc_with_iv = (type(iv)=="string" and #iv == 16) and
            assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv=iv})) or nil

    for _, ssl in ipairs(ssl_items) do
        if type(ssl) == "table" and
            ssl.value ~= nil and
            (ssl.value.status == nil or ssl.value.status == 1) then  -- compatible with old version

            local j = 0
            local sni
            if type(ssl.value.snis) == "table" and #ssl.value.snis > 0 then
                sni = core.table.new(0, #ssl.value.snis)
                for _, s in ipairs(ssl.value.snis) do
                    j = j + 1
                    sni[j] = s:reverse()
                end
            else
                sni = ssl.value.sni:reverse()
            end

            -- decrypt private key
            if aes_128_cbc_with_iv ~= nil and
                not str_find(ssl.value.key, "---") then
                local decrypted = aes_128_cbc_with_iv:decrypt(ngx_decode_base64(ssl.value.key))
                if decrypted == nil then
                    core.log.error("decrypt ssl key failed. key[", ssl.value.key, "] ")
                else
                    ssl.value.key = decrypted
                end
            end

            local
            idx = idx + 1
            route_items[idx] = {
                paths = sni,
                handler = function (api_ctx)
                    if not api_ctx then
                        return
                    end
                    api_ctx.matched_ssl = ssl
                    api_ctx.matched_sni = sni
                end
            }
        end
    end

    core.log.info("route items: ", core.json.delay_encode(route_items, true))
    local router, err = radixtree_new(route_items)
    if not router then
        return nil, err
    end

    return router
end


local function set_pem_ssl_key(cert, pkey)
    local r = get_request()
    if r == nil then
        return false, "no request found"
    end

    ngx_ssl.clear_certs()

    local parse_cert, err = ngx_ssl.parse_pem_cert(cert)
    if parse_cert then
        local ok, err = ngx_ssl.set_cert(parse_cert)
        if not ok then
            return false, "failed to set PEM cert: " .. err
        end
    else
        return false, "failed to parse PEM cert: " .. err
    end

    local parse_pkey, err = ngx_ssl.parse_pem_priv_key(pkey)
    if parse_pkey then
        local ok, err = ngx_ssl.set_priv_key(parse_pkey)
        if not ok then
            return false, "failed to set PEM priv key: " .. err
        end
    else
        return false, "failed to parse PEM priv key: " .. err
    end

    return true
end


function _M.match_and_set(api_ctx)
    local err
    if not radixtree_router or
       radixtree_router_ver ~= ssl_certificates.conf_version then
        radixtree_router, err = create_router(ssl_certificates.values)
        if not radixtree_router then
            return false, "failed to create radixtree router: " .. err
        end
        radixtree_router_ver = ssl_certificates.conf_version
    end

    local sni
    sni, err = ngx_ssl.server_name()
    if type(sni) ~= "string" then
        return false, "failed to fetch SNI: " .. (err or "not found")
    end

    core.log.debug("sni: ", sni)

    local sni_rev = sni:reverse()
    local ok = radixtree_router:dispatch(sni_rev, nil, api_ctx)
    if not ok then
        core.log.warn("not found any valid sni configuration")
        return false
    end


    if type(api_ctx.matched_sni) == "table" then
        local matched = false
        for _, msni in ipairs(api_ctx.matched_sni) do
            if sni_rev == msni or not str_find(sni_rev, ".", #msni, true) then
                matched = true
            end
        end
        if not matched then
            core.log.warn("not found any valid sni configuration, matched sni: ",
                          core.json.delay_encode(api_ctx.matched_sni, true), " current sni: ", sni)
            return false
        end
    else
        if str_find(sni_rev, ".", #api_ctx.matched_sni, true) then
            core.log.warn("not found any valid sni configuration, matched sni: ",
                          api_ctx.matched_sni:reverse(), " current sni: ", sni)
            return false
        end
    end

    local matched_ssl = api_ctx.matched_ssl
    core.log.info("debug - matched: ", core.json.delay_encode(matched_ssl, true))
    ok, err = set_pem_ssl_key(matched_ssl.value.cert, matched_ssl.value.key)
    if not ok then
        return false, err
    end

    return true
end


function _M.init_worker()
    local err
    ssl_certificates, err = core.config.new("/ssl", {
                        automatic = true,
                        item_schema = core.schema.ssl,
                    })
    if not ssl_certificates then
        error("failed to create etcd instance for fetching ssl certificates: "
              .. err)
    end
end


return _M
