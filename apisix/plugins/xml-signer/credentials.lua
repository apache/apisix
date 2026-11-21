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

local ngx_time = ngx.time
local os_date = os.date
local tostring = tostring
local type = type

-- RSA keys shorter than 2048 bits are considered insecure (NIST SP 800-131A).
-- Callers may lower the minimum for legacy algorithms.
local DEFAULT_MIN_RSA_KEY_BITS = 2048


local credential_cache = core.lrucache.new({
    ttl = 300,
    count = 64,
})

local _M = {}


local function format_time(timestamp)
    return os_date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
end


-- Verifiers reject signatures made with a certificate outside its validity
-- period. Signing still proceeds, so a configuration change cannot break
-- traffic, but the operator is warned whenever the credentials are loaded.
local function warn_if_outside_validity(certificate)
    local now = ngx_time()
    local not_before = certificate:get_not_before()
    local not_after = certificate:get_not_after()
    if not_after and not_after < now then
        core.log.warn("the signing certificate expired at ", format_time(not_after),
                      "; verifiers will reject the signatures")
    elseif not_before and not_before > now then
        core.log.warn("the signing certificate is not valid before ",
                      format_time(not_before), "; verifiers will reject the signatures")
    end
end


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
    -- get_size() returns the maximum signature size in bytes, which is the
    -- RSA modulus length.
    local key_size = private_key:get_size()
    if not key_size then
        return nil, "cannot determine RSA private key size"
    end

    local certificate, certificate_err = x509.new(certificate_pem, "PEM")
    if not certificate then
        return nil, "cannot parse X.509 certificate: " .. tostring(certificate_err)
    end

    local matches, match_err = certificate:check_private_key(private_key)
    if not matches then
        return nil, "private key does not match certificate: " .. tostring(match_err)
    end
    warn_if_outside_validity(certificate)

    local certificate_der, der_err = certificate:tostring("DER")
    if not certificate_der then
        return nil, "cannot encode X.509 certificate: " .. tostring(der_err)
    end

    return {
        private_key = private_key,
        certificate = certificate,
        certificate_der = certificate_der,
        key_bits = key_size * 8,
    }
end


-- min_key_bits defaults to 2048. The size is checked after the cache lookup
-- so that one key pair can be shared by Routes with different minimums.
function _M.load(conf, min_key_bits)
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
    local runtime, err = credential_cache(cache_key, nil, parse_credentials,
                                          certificate_pem, private_key_pem)
    if not runtime then
        return nil, err
    end

    min_key_bits = min_key_bits or DEFAULT_MIN_RSA_KEY_BITS
    if runtime.key_bits < min_key_bits then
        return nil, "RSA private key must be at least " .. min_key_bits .. " bits"
    end
    return runtime
end


return _M
