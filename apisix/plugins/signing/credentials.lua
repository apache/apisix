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
local pkey = require("resty.openssl.pkey")
local resty_sha256 = require("resty.sha256")
local resty_string = require("resty.string")
local x509 = require("resty.openssl.x509")

local tostring = tostring
local type = type


local credential_cache = core.lrucache.new({
    ttl = 300,
    count = 64,
})

local _M = {}


local function fingerprint(certificate_pem, private_key_pem)
    local sha256 = resty_sha256:new()
    sha256:update(certificate_pem)
    sha256:update("\0")
    sha256:update(private_key_pem)
    return resty_string.to_hex(sha256:final())
end


local function parse_credentials(certificate_pem, private_key_pem)
    local private_key, key_err = pkey.new(private_key_pem, {
        format = "PEM",
        type = "pr",
    })
    if not private_key then
        return nil, "cannot parse RSA private key: " .. tostring(key_err)
    end
    local key_type = private_key:get_key_type()
    if not key_type or key_type.sn ~= "rsaEncryption" then
        return nil, "private key must be RSA"
    end

    local certificate, certificate_err = x509.new(certificate_pem, "PEM")
    if not certificate then
        return nil, "cannot parse X.509 certificate: " .. tostring(certificate_err)
    end

    local matches, match_err = certificate:check_private_key(private_key)
    if not matches then
        return nil, "private key does not match certificate: " .. tostring(match_err)
    end

    local certificate_der, der_err = certificate:tostring("DER")
    if not certificate_der then
        return nil, "cannot encode X.509 certificate: " .. tostring(der_err)
    end

    return {
        private_key = private_key,
        certificate = certificate,
        certificate_der = certificate_der,
    }
end


function _M.load(conf)
    if type(conf) ~= "table" then
        return nil, "credentials are required"
    end

    local certificate_pem = conf.certificate
    local private_key_pem = conf.private_key
    if type(certificate_pem) ~= "string" or certificate_pem == "" then
        return nil, "certificate is required"
    end
    if type(private_key_pem) ~= "string" or private_key_pem == "" then
        return nil, "private key is required"
    end
    if certificate_pem:sub(1, 1) == "$" or private_key_pem:sub(1, 1) == "$" then
        return nil, "credential secret reference could not be resolved"
    end

    local cache_key = fingerprint(certificate_pem, private_key_pem)
    return credential_cache(cache_key, nil, parse_credentials,
                            certificate_pem, private_key_pem)
end


return _M