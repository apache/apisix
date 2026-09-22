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
-- DPoP test helper.
-- Loaded from test blocks as require("lib.dpop").
local cjson = require("cjson.safe")
local openssl_pkey = require("resty.openssl.pkey")
local resty_sha256 = require("resty.sha256")
local string_format = string.format
local ngx = ngx

local _M = {}

-- base64url without padding
function _M.b64url_encode(bytes)
    local b = ngx.encode_base64(bytes)
    return (b:gsub("+", "-"):gsub("/", "_"):gsub("=", ""))
end

-- DER ECDSA-Sig (SEQUENCE of two INTEGERs) → raw R||S of fixed width.
-- Layout: 0x30 <seq_len> 0x02 <r_len> <r> 0x02 <s_len> <s>.
-- <seq_len> may be short form (one byte, value < 128) or long form
-- (0x81 <len> for 128-255, 0x82 <hi> <lo> for 256-65535). ES512
-- signatures regularly exceed the short-form limit.
function _M.der_to_raw_ecdsa(der, comp_size)
    -- pos starts at 2 (just past the SEQUENCE tag 0x30)
    local pos = 2
    local first = der:byte(pos)
    if first == 0x81 then
        pos = pos + 2          -- skip 0x81 + 1 length byte
    elseif first == 0x82 then
        pos = pos + 3          -- skip 0x82 + 2 length bytes
    else
        pos = pos + 1          -- short form: just the length byte
    end
    pos = pos + 1              -- skip 0x02 INTEGER tag for r
    local r_len = der:byte(pos)
    pos = pos + 1
    local r = der:sub(pos, pos + r_len - 1)
    pos = pos + r_len + 1      -- skip past r and the 0x02 INTEGER tag for s
    local s_len = der:byte(pos)
    pos = pos + 1
    local s = der:sub(pos, pos + s_len - 1)
    while #r > comp_size do r = r:sub(2) end
    while #s > comp_size do s = s:sub(2) end
    while #r < comp_size do r = "\0" .. r end
    while #s < comp_size do s = "\0" .. s end
    return r .. s
end

local function sha256_b64url(bytes)
    local sha = resty_sha256:new()
    sha:update(bytes)
    return _M.b64url_encode(sha:final())
end
_M.sha256_b64url = sha256_b64url

-- EC keypair. curve ∈ {"prime256v1" (P-256), "secp384r1" (P-384), "secp521r1" (P-521)}.
-- Returns pkey, jwk_table, thumbprint_b64url (RFC 7638).
function _M.new_ec_keypair(curve)
    local pkey = openssl_pkey.new({ type = "EC", curve = curve })
    local p = pkey:get_parameters()
    local crv
    if curve == "prime256v1" then
        crv = "P-256"
    elseif curve == "secp384r1" then
        crv = "P-384"
    elseif curve == "secp521r1" then
        crv = "P-521"
    else
        error("unsupported EC curve: " .. tostring(curve))
    end
    local jwk = {
        kty = "EC", crv = crv,
        x = _M.b64url_encode(p.x:to_binary()),
        y = _M.b64url_encode(p.y:to_binary()),
    }
    -- RFC 7638 EC thumbprint: lex-sorted {crv, kty, x, y}
    local input = string_format(
        '{"crv":"%s","kty":"EC","x":"%s","y":"%s"}',
        jwk.crv, jwk.x, jwk.y
    )
    return pkey, jwk, sha256_b64url(input)
end

-- RSA keypair. bits default 2048.
-- Returns pkey, jwk_table, thumbprint_b64url (RFC 7638).
function _M.new_rsa_keypair(bits)
    bits = bits or 2048
    local pkey = openssl_pkey.new({ type = "RSA", bits = bits })
    local p = pkey:get_parameters()
    local jwk = {
        kty = "RSA",
        n = _M.b64url_encode(p.n:to_binary()),
        e = _M.b64url_encode(p.e:to_binary()),
    }
    -- RFC 7638 RSA thumbprint: lex-sorted {e, kty, n}
    local input = string_format(
        '{"e":"%s","kty":"RSA","n":"%s"}',
        jwk.e, jwk.n
    )
    return pkey, jwk, sha256_b64url(input)
end

-- alg=none access token: "{alg:none,typ:JWT}.{sub,cnf.jkt,exp}."
-- overrides: { sub, cnf_jkt, exp, extra = {...} }
function _M.make_alg_none_access_token(thumbprint, overrides)
    overrides = overrides or {}
    local payload = {
        sub = overrides.sub or "testuser",
        cnf = { jkt = overrides.cnf_jkt or thumbprint },
        exp = overrides.exp or (ngx.time() + 3600),
    }
    if overrides.extra then
        for k, v in pairs(overrides.extra) do payload[k] = v end
    end
    local h = _M.b64url_encode(cjson.encode({ alg = "none", typ = "JWT" }))
    local p = _M.b64url_encode(cjson.encode(payload))
    return h .. "." .. p .. "."
end

local DIGEST = {
    ES256 = "sha256", ES384 = "sha384", ES512 = "sha512",
    RS256 = "sha256", RS384 = "sha384", RS512 = "sha512",
    PS256 = "sha256", PS384 = "sha384", PS512 = "sha512",
}
local EC_COMP = { ES256 = 32, ES384 = 48, ES512 = 66 }
local PSS_SALTLEN = { PS256 = 32, PS384 = 48, PS512 = 64 }

-- Build and sign a DPoP proof.
-- opts:
--   pkey, jwk, alg                (required; alg ∈ ES256/ES384/ES512/
--                                  RS256/RS384/RS512/PS256/PS384/PS512/none)
--   htm, htu, iat, jti, ath       (claims; nil means "do not include")
--   typ                           (defaults to "dpop+jwt")
--   extra_header, extra_payload   (merged into header/payload tables)
--   omit = { "claim", ... }       (final pass: removes these claim keys)
--   raw_signature                 (if set: skip signing, use these bytes)
function _M.make_dpop_proof(opts)
    local header = {
        typ = opts.typ or "dpop+jwt",
        alg = opts.alg,
        jwk = opts.jwk,
    }
    if opts.extra_header then
        for k, v in pairs(opts.extra_header) do header[k] = v end
    end

    local payload = {}
    if opts.htm ~= nil then payload.htm = opts.htm end
    if opts.htu ~= nil then payload.htu = opts.htu end
    if opts.iat ~= nil then payload.iat = opts.iat end
    if opts.jti ~= nil then payload.jti = opts.jti end
    if opts.ath ~= nil then payload.ath = opts.ath end
    if opts.extra_payload then
        for k, v in pairs(opts.extra_payload) do payload[k] = v end
    end
    if opts.omit then
        for _, key in ipairs(opts.omit) do payload[key] = nil end
    end

    local h_b64 = _M.b64url_encode(cjson.encode(header))
    local p_b64 = _M.b64url_encode(cjson.encode(payload))
    local signing_input = h_b64 .. "." .. p_b64

    local sig_b64
    if opts.raw_signature ~= nil then
        sig_b64 = _M.b64url_encode(opts.raw_signature)
    elseif opts.alg == "none" then
        sig_b64 = ""
    else
        local digest = DIGEST[opts.alg]
        if not digest then
            error("unsupported alg: " .. tostring(opts.alg))
        end
        local sig
        if PSS_SALTLEN[opts.alg] then
            -- 4th arg = padding (6 = RSA_PKCS1_PSS_PADDING). lua-resty-openssl
            -- applies the padding via EVP_PKEY_CTX_set_rsa_padding before any
            -- opts, satisfying OpenSSL 3 provider's parameter-order check.
            -- Explicit pss_saltlen matches JWS RFC 7518 §3.5 (= digest size).
            sig = opts.pkey:sign(signing_input, digest, 6,
                { pss_saltlen = PSS_SALTLEN[opts.alg] })
        else
            sig = opts.pkey:sign(signing_input, digest)
        end
        if EC_COMP[opts.alg] then
            sig = _M.der_to_raw_ecdsa(sig, EC_COMP[opts.alg])
        end
        sig_b64 = _M.b64url_encode(sig)
    end

    return signing_input .. "." .. sig_b64
end

-- Convenience: full happy-flow components.
-- alg ∈ {"ES256","ES384","ES512","RS256","RS384","RS512","PS256","PS384","PS512"}.
-- proof_overrides may override any claim or pass extras to make_dpop_proof.
-- Returns: { access_token, proof, jwk, thumbprint, pkey }.
function _M.valid_flow(alg, proof_overrides)
    local pkey, jwk, thumbprint
    if alg == "ES256" then
        pkey, jwk, thumbprint = _M.new_ec_keypair("prime256v1")
    elseif alg == "ES384" then
        pkey, jwk, thumbprint = _M.new_ec_keypair("secp384r1")
    elseif alg == "ES512" then
        pkey, jwk, thumbprint = _M.new_ec_keypair("secp521r1")
    elseif alg == "RS256" or alg == "RS384" or alg == "RS512"
        or alg == "PS256" or alg == "PS384" or alg == "PS512" then
        pkey, jwk, thumbprint = _M.new_rsa_keypair(2048)
    else
        error("unsupported alg: " .. tostring(alg))
    end

    local access_token = _M.make_alg_none_access_token(thumbprint)
    local ath = sha256_b64url(access_token)

    proof_overrides = proof_overrides or {}
    local opts = {
        pkey = pkey,
        jwk = proof_overrides.jwk or jwk,
        alg = proof_overrides.alg or alg,
        htm = proof_overrides.htm or "GET",
        htu = proof_overrides.htu or "http://localhost/hello",
        iat = proof_overrides.iat or ngx.time(),
        jti = proof_overrides.jti
            or (alg:lower() .. "-" .. tostring(ngx.now())),
        ath = proof_overrides.ath ~= nil and proof_overrides.ath or ath,
        typ = proof_overrides.typ,
        extra_header = proof_overrides.extra_header,
        extra_payload = proof_overrides.extra_payload,
        omit = proof_overrides.omit,
        raw_signature = proof_overrides.raw_signature,
    }
    local proof = _M.make_dpop_proof(opts)
    return {
        access_token = access_token,
        proof = proof,
        jwk = jwk,
        thumbprint = thumbprint,
        pkey = pkey,
    }
end

return _M
