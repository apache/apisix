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

local buffer = require "string.buffer"
local openssl_digest = require "resty.openssl.digest"
local openssl_mac = require "resty.openssl.mac"
local openssl_pkey = require "resty.openssl.pkey"
local base64 = require "ngx.base64"
local core = require "apisix.core"
local jwt = require("resty.jwt")

local ngx_time = ngx.time
local http_time = ngx.http_time
local string_fmt = string.format
local assert = assert
local setmetatable = setmetatable
local ipairs = ipairs
local type = type
local error = error
local pcall = pcall
local tostring = tostring

local default_claims = {
    "nbf",
    "exp"
}

local alg_sign = {
    HS256 = function(data, key)
        return openssl_mac.new(key, "HMAC", nil, "sha256"):final(data)
    end,
    HS384 = function(data, key)
        return openssl_mac.new(key, "HMAC", nil, "sha384"):final(data)
    end,
    HS512 = function(data, key)
        return openssl_mac.new(key, "HMAC", nil, "sha512"):final(data)
    end,
    RS256 = function(data, key)
        local digest = openssl_digest.new("sha256")
        assert(digest:update(data))
        return assert(openssl_pkey.new(key):sign(digest))
    end,
    RS384 = function(data, key)
        local digest = openssl_digest.new("sha384")
        assert(digest:update(data))
        return assert(openssl_pkey.new(key):sign(digest))
    end,
    RS512 = function(data, key)
        local digest = openssl_digest.new("sha512")
        assert(digest:update(data))
        return assert(openssl_pkey.new(key):sign(digest))
    end,
    ES256 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha256", nil, {ecdsa_use_raw = true}))
        if not sig then
            return nil
        end
        return sig
    end,
    ES384 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha384", nil, {ecdsa_use_raw = true}))
        if not sig then
            return nil
        end
        return sig
    end,
    ES512 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha512", nil, {ecdsa_use_raw = true}))
        if not sig then
            return nil
        end
        return sig
    end,
    PS256 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha256", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING))
        if not sig then
            return nil
        end
        return sig
    end,
    PS384 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha384", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING))
        if not sig then
            return nil
        end
        return sig
    end,
    PS512 = function(data, key)
        local pkey = openssl_pkey.new(key)
        local sig = assert(pkey:sign(data, "sha512", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING))
        if not sig then
            return nil
        end
        return sig
    end,
    EdDSA = function(data, key)
        local pkey = assert(openssl_pkey.new(key))
        return assert(pkey:sign(data))
    end
}

local alg_verify = {
    HS256 = function(data, signature, key)
        return signature == alg_sign.HS256(data, key)
    end,
    HS384 = function(data, signature, key)
        return signature == alg_sign.HS384(data, key)
    end,
    HS512 = function(data, signature, key)
        return signature == alg_sign.HS512(data, key)
    end,
    RS256 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        return pkey:verify(signature, data, "sha256")
    end,
    RS384 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        return pkey:verify(signature, data, "sha384")
    end,
    RS512 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        return pkey:verify(signature, data, "sha512")
    end,
    ES256 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 64, "Signature must be 64 bytes.")
        return pkey:verify(signature, data, "sha256", nil, {ecdsa_use_raw = true})
    end,
    ES384 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 96, "Signature must be 96 bytes.")
        return pkey:verify(signature, data, "sha384", nil, {ecdsa_use_raw = true})
    end,
    ES512 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 132, "Signature must be 132 bytes.")
        return pkey:verify(signature, data, "sha512", nil, {ecdsa_use_raw = true})
    end,
    PS256 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 256, "Signature must be 256 bytes")
        return pkey:verify(signature, data, "sha256", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING)
    end,
    PS384 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 256, "Signature must be 256 bytes")
        return pkey:verify(signature, data, "sha384", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING)
    end,
    PS512 = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        assert(#signature == 256, "Signature must be 256 bytes")
        return pkey:verify(signature, data, "sha512", openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING)
    end,
    EdDSA = function(data, signature, key)
        local pkey, _ = openssl_pkey.new(key)
        assert(pkey, "Consumer Public Key is Invalid")
        return pkey:verify(signature, data)
    end
}

local claims_checker = {
    nbf = {
        type = "number",
        check = function(nbf, conf)
            local clock_leeway = conf and conf.lifetime_grace_period or 0
            if nbf < ngx_time() + clock_leeway then
                return true
            end
            return false, string_fmt("'nbf' claim not valid until %s", http_time(nbf))
        end
    },
    exp = {
        type = "number",
        check = function(exp, conf)
            local clock_leeway = conf and conf.lifetime_grace_period or 0
            if exp > ngx_time() - clock_leeway then
                return true
            end
            return false, string_fmt("'exp' claim expired at %s", http_time(exp))
        end
    }
}

local base64_encode = base64.encode_base64url
local base64_decode = base64.decode_base64url

local _M = {}

function _M.new(token)
    local jwt_obj = jwt:load_jwt(token)
    if type(jwt_obj) == "table" and not jwt_obj.valid then
        return nil, jwt_obj.reason
    end
    return setmetatable(jwt_obj, {__index = _M})
end


function _M.verify_signature(self, key)
    local verifier = alg_verify[self.header.alg]
    if not verifier then
        return false, "unsupported algorithm: " .. tostring(self.header.alg)
    end

    local signature = base64_decode(self.signature)
    if not signature then
        return false, "failed to decode signature"
    end

    -- the per-algorithm verifiers assert on signature length and key validity,
    -- so guard with pcall to turn a malformed token into a clean rejection
    -- instead of letting the error propagate as a 500 response
    local ok, verified, verify_err = pcall(verifier,
        self.raw_header .. "." .. self.raw_payload, signature, key)
    if not ok then
        -- verifier raised: `verified` holds the caught error message
        return false, verified
    end

    -- preserve the verifier's own (verified, err) return contract
    return verified, verify_err
end


function _M.verify_claims(self, claims, conf)
    -- When `claims_to_verify` is not configured (nil or an explicitly empty
    -- array), fall back to the default claims (exp/nbf) and validate them only
    -- if they are present in the payload. This closes the expired-token hole
    -- while staying lenient for tokens that legitimately omit these claims.
    -- An empty array must NOT skip validation, otherwise it reopens the bypass.
    if not claims or #claims == 0 then
        for _, claim_name in ipairs(default_claims) do
            local claim = self.payload[claim_name]
            if claim ~= nil then
                local checker = claims_checker[claim_name]
                if type(claim) ~= checker.type then
                    return false, "claim " .. claim_name .. " is not a " .. checker.type
                end
                local ok, err = checker.check(claim, conf)
                if not ok then
                    return false, err
                end
            end
        end

        return true
    end

    -- When `claims_to_verify` is explicitly configured, the listed claims are
    -- required: they must exist in the payload and be valid.
    for _, claim_name in ipairs(claims) do
        local claim = self.payload[claim_name]
        if claim == nil then
            return false, "claim " .. claim_name .. " is missing"
        end
        local checker = claims_checker[claim_name]
        if type(claim) ~= checker.type then
            return false, "claim " .. claim_name .. " is not a " .. checker.type
        end
        local ok, err = checker.check(claim, conf)
        if not ok then
            return false, err
        end
    end

    return true
end


function _M.encode(alg, key, header, data)
    alg = alg or "HS256"
    if not alg_sign[alg] then
        return nil, "algorithm not supported"
    end

    if type(key) ~= "string" then
        error("Argument #2 must be string", 2)
        return nil, "key must be a string"
    end

    if header and type(header) ~= "table" then
        return nil, "header must be a table"
    end

    if type(data) ~= "table" then
        return nil, "data must be a table"
    end

    local header = header or {typ = "JWT", alg = alg}
    local buf = buffer.new()

    buf:put(base64_encode(core.json.encode(header)))
        :put(".")
        :put(base64_encode(core.json.encode(data)))

    local ok, signature = pcall(alg_sign[alg], buf:tostring(), key)
    if not ok then
        return nil, signature
    end

    buf:put("."):put(base64_encode(signature))

    return buf:get()
end

return _M
