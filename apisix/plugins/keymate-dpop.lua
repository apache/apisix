local core = require("apisix.core")
local cjson = require("cjson.safe")
local resty_sha256 = require("resty.sha256")
local http = require("resty.http")
local openssl_pkey = require("resty.openssl.pkey")
local lrucache = require("resty.lrucache")
local ngx = ngx

local plugin_name = "keymate-dpop"

-- Module-level local JTI cache — fallback when ngx.shared.dpop_jti_cache
-- is not configured. Per-worker only; ensures fail-closed per RFC 9449 §11.1.
local _jti_local_cache = {}
local _jti_local_count = 0

local function jti_local_cleanup()
    local now = ngx.time()
    local new_count = 0
    for k, expiry in pairs(_jti_local_cache) do
        if expiry <= now then
            _jti_local_cache[k] = nil
        else
            new_count = new_count + 1
        end
    end
    _jti_local_count = new_count
end

-- PKey LRU cache: JWK JSON → openssl pkey object
-- 128 entries is generous — typical deployment has 1-3 signing keys
local _pkey_cache, pkey_cache_err = lrucache.new(128)
if not _pkey_cache then
    error("failed to create pkey LRU cache: " .. (pkey_cache_err or "unknown"))
end

-- Module-level JWKS caches
local _jwks_cache = {}           -- jwks_uri -> { keys_by_kid = {kid -> jwk_table}, fetched_at }
local _discovery_cache = {}      -- discovery_url -> { jwks_uri, fetched_at }
local _jwks_last_refetch = 0     -- rate limit: max 1 refetch per 60s

-- Introspection cache: module-level local fallback when ngx.shared.dpop_intro_cache
-- is not configured. Per-worker only; shared dict preferred for cross-worker consistency.
local _introspection_cache = {}
local _introspection_cache_count = 0

-- Infinispan digest auth nonce cache (per-worker)
local _ispn_digest_cache = {}  -- endpoint -> { nonce, realm, qop, nc }

-- HTTP Digest Auth helper: parse WWW-Authenticate header and compute Authorization
local function ispn_digest_auth(www_auth, method, uri, username, password)
    if not www_auth then return nil end
    local realm = www_auth:match('realm="([^"]+)"')
    local nonce = www_auth:match('nonce="([^"]+)"')
    local qop   = www_auth:match('qop="([^"]*)"') or www_auth:match('qop=([^,% ]+)')
    if not realm or not nonce then return nil end
    local nc = "00000001"
    local cnonce = ngx.md5(tostring(ngx.now()) .. tostring(math.random(1, 999999)))
    local ha1 = ngx.md5(username .. ":" .. realm .. ":" .. password)
    local ha2 = ngx.md5(method .. ":" .. uri)
    local response
    if qop and qop:find("auth") then
        response = ngx.md5(ha1 .. ":" .. nonce .. ":" .. nc
            .. ":" .. cnonce .. ":" .. "auth" .. ":" .. ha2)
    else
        response = ngx.md5(ha1 .. ":" .. nonce .. ":" .. ha2)
    end
    return 'Digest username="' .. username
        .. '", realm="' .. realm
        .. '", nonce="' .. nonce
        .. '", uri="' .. uri
        .. '", qop=auth, nc=' .. nc
        .. ', cnonce="' .. cnonce
        .. '", response="' .. response .. '"',
        nonce, realm, qop
end

local schema = {
    type = "object",
    properties = {
        allowed_algs = {
            type = "array",
            items = {
                type = "string",
                enum = {
                    "ES256", "ES384", "ES512",
                    "RS256", "RS384", "RS512",
                    "PS256", "PS384", "PS512",
                },
            },
            default = {"ES256"},
            minItems = 1,
            uniqueItems = true,
        },
        proof_max_age = {
            type = "integer",
            default = 120,
            minimum = 1,
        },
        clock_skew_seconds = {
            type = "integer",
            default = 5,
            minimum = 0,
        },
        replay_cache = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"memory", "redis", "ispn"},
                    default = "memory",
                },
                fallback = {
                    type = "string",
                    enum = {"memory", "bypass", "reject"},
                    default = "memory",
                },
                ttl = {
                    type = "integer",
                    minimum = 10,
                    -- When omitted, falls back to proof_max_age at runtime
                },
                redis = {
                    type = "object",
                    properties = {
                        host = { type = "string", minLength = 1 },
                        port = { type = "integer", default = 6379, minimum = 1, maximum = 65535 },
                        password = { type = "string" },
                        timeout = { type = "integer", default = 2000, minimum = 100 },
                    },
                },
                ispn = {
                    type = "object",
                    properties = {
                        endpoint = { type = "string", minLength = 1 },
                        cache_name = { type = "string", default = "dpop-jti", minLength = 1 },
                        username = { type = "string" },
                        password = { type = "string" },
                    },
                },
            },
        },
        strict_htu = {
            type = "boolean",
            default = false
        },
        public_base_url = {
            type = "string",
            default = "",
            pattern = "^$|^https?://",
        },
        require_nonce = {
            type = "boolean",
            default = false
        },
        send_thumbprint_header = {
            type = "boolean",
            default = true
        },
        discovery = {
            type = "string",
            pattern = "^https?://",
        },
        jwks_uri = {
            type = "string",
            pattern = "^https?://",
        },
        token_signing_algorithm = {
            type = "string",
            default = "RS256",
            enum = {"RS256", "RS384", "RS512"},
        },
        jwks_cache_ttl = {
            type = "integer",
            default = 86400,
            minimum = 60,
            maximum = 604800,
        },
        verify_access_token = {
            type = "boolean",
            default = true,
        },
        introspection_endpoint = {
            type = "string",
            pattern = "^https?://",
        },
        introspection_client_id = {
            type = "string",
            minLength = 1,
        },
        introspection_client_secret = {
            type = "string",
        },
        introspection_cache_ttl = {
            type = "integer",
            default = 0,
            minimum = 0,
            maximum = 3600,
        },
        enforce_introspection = {
            type = "boolean",
            default = false,
        },
        uri_allow = {
            type = "array",
            items = { type = "string", minLength = 1 },
            default = {},
            uniqueItems = true,
        },
        token_issuer = {
            type = "string",
            default = "",
        },
    },
    additionalProperties = false,
}

local _M = {
    version = 0.1,
    priority = 2601,
    name = plugin_name,
    schema = schema,
    description = "RFC 9449 DPoP (Demonstrating Proof of Possession) "
        .. "proof validation for sender-constrained access tokens.",
}

function _M.check_schema(conf, schema_type)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    -- Security Guardrail: Prevent Replay Vulnerability
    -- replay_cache.ttl must be >= proof_max_age + clock_skew_seconds
    local max_age = conf.proof_max_age or 120
    local skew = conf.clock_skew_seconds or 5
    local required_ttl = max_age + skew

    if conf.replay_cache and conf.replay_cache.ttl and conf.replay_cache.ttl > 0 then
        if conf.replay_cache.ttl < required_ttl then
            return false, "SECURITY ERROR: replay_cache.ttl (" .. conf.replay_cache.ttl
                .. ") must be >= proof_max_age + clock_skew_seconds (" .. required_ttl
                .. ") to prevent replay attacks."
        end
    end

    -- Dependency: enforce_introspection requires introspection_endpoint
    if conf.enforce_introspection then
        if not conf.introspection_endpoint or conf.introspection_endpoint == "" then
            return false, "enforce_introspection=true requires introspection_endpoint"
        end
    end

    -- Dependency: strict_htu requires public_base_url
    if conf.strict_htu then
        if not conf.public_base_url or conf.public_base_url == "" then
            return false, "strict_htu=true requires public_base_url"
        end
    end

    -- Dependency: replay_cache.type=redis requires redis.host
    if conf.replay_cache and conf.replay_cache.type == "redis" then
        if not conf.replay_cache.redis
            or not conf.replay_cache.redis.host
            or conf.replay_cache.redis.host == "" then
            return false, "replay_cache.type=redis requires replay_cache.redis.host"
        end
    end

    -- Dependency: replay_cache.type=ispn requires ispn.endpoint
    if conf.replay_cache and conf.replay_cache.type == "ispn" then
        if not conf.replay_cache.ispn
            or not conf.replay_cache.ispn.endpoint
            or conf.replay_cache.ispn.endpoint == "" then
            return false, "replay_cache.type=ispn requires replay_cache.ispn.endpoint"
        end
    end

    return true
end

-- ===========================================================================
-- Helpers
-- ===========================================================================

local function base64url_decode(input)
    local s = input:gsub("-", "+"):gsub("_", "/")
    local pad = #s % 4
    if pad == 2 then
        s = s .. "=="
    elseif pad == 3 then
        s = s .. "="
    end
    return ngx.decode_base64(s)
end


local function base64url_encode(input)
    local b64 = ngx.encode_base64(input)
    return b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end


local function sha256_b64url(data)
    local sha = resty_sha256:new()
    sha:update(data)
    local digest = sha:final()
    return base64url_encode(digest)
end

-- Structured audit log — one line per DPoP decision (success or failure)
local function dpop_audit(result, err_code, desc, method, uri, jti, issuer, client_id)
    local trace_id = ngx.var.opentelemetry_trace_id or ""

    core.log.warn("[DPoP-Audit] ",
        cjson.encode({
            result = result,
            error = err_code,
            desc = desc,
            method = method,
            uri = uri,
            jti = jti,
            issuer = issuer or "",
            client_id = client_id or "",
            trace_id = trace_id,
        }))
end


local function dpop_error(err_code, desc)
    ngx.header["WWW-Authenticate"] = 'DPoP error="' .. err_code .. '"'
        .. (desc and (', error_description="' .. desc .. '"') or "")
    return 401, { error = err_code, error_description = desc }
end


local function parse_jwt(token)
    local parts = {}
    for part in token:gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end

    if #parts ~= 3 then
        return nil, "invalid JWT: expected 3 parts, got " .. #parts
    end

    local header_json = base64url_decode(parts[1])
    if not header_json then
        return nil, "invalid JWT: failed to decode header"
    end

    local payload_json = base64url_decode(parts[2])
    if not payload_json then
        return nil, "invalid JWT: failed to decode payload"
    end

    local header, h_err = cjson.decode(header_json)
    if not header then
        return nil, "invalid JWT: failed to parse header JSON: " .. (h_err or "unknown")
    end

    local payload, p_err = cjson.decode(payload_json)
    if not payload then
        return nil, "invalid JWT: failed to parse payload JSON: " .. (p_err or "unknown")
    end

    return {
        header = header,
        payload = payload,
        raw_parts = parts,
    }
end


local function extract_path(url)
    -- Extract path from full URL, stripping query/fragment
    local path = url:match("^https?://[^/]+(/.*)$") or url
    path = path:match("^([^%?#]*)") or path
    return path
end

-- RFC 7638 JWK Thumbprint
local function compute_jwk_thumbprint(jwk)
    if not jwk or not jwk.kty then
        return nil, "jwk missing or no kty"
    end

    local canonical
    if jwk.kty == "EC" then
        if not jwk.crv or not jwk.x or not jwk.y then
            return nil, "EC key missing crv, x, or y"
        end
        -- RFC 7638: members in lexicographic order
        canonical = '{"crv":"' .. jwk.crv .. '","kty":"' .. jwk.kty
            .. '","x":"' .. jwk.x .. '","y":"' .. jwk.y .. '"}'
    elseif jwk.kty == "RSA" then
        if not jwk.e or not jwk.n then
            return nil, "RSA key missing e or n"
        end
        canonical = '{"e":"' .. jwk.e .. '","kty":"' .. jwk.kty
            .. '","n":"' .. jwk.n .. '"}'
    elseif jwk.kty == "OKP" then
        if not jwk.crv or not jwk.x then
            return nil, "OKP key missing crv or x"
        end
        canonical = '{"crv":"' .. jwk.crv .. '","kty":"' .. jwk.kty
            .. '","x":"' .. jwk.x .. '"}'
    else
        return nil, "unsupported key type: " .. jwk.kty
    end

    local sha = resty_sha256:new()
    sha:update(canonical)
    local digest = sha:final()

    return base64url_encode(digest)
end

-- Get or create openssl pkey from JWK, cached by JSON representation
local function get_or_create_pkey(jwk)
    local jwk_json = cjson.encode(jwk)
    local pkey = _pkey_cache:get(jwk_json)
    if pkey then
        return pkey
    end
    local new_pkey, err = openssl_pkey.new(jwk_json, { format = "JWK" })
    if not new_pkey then
        return nil, err
    end
    _pkey_cache:set(jwk_json, new_pkey, 3600)  -- 1 hour TTL
    return new_pkey
end

-- ===========================================================================
-- JWKS fetching + Access Token Signature Verification
-- ===========================================================================

local function resolve_jwks_uri(conf)
    -- Direct jwks_uri takes precedence
    if conf.jwks_uri and conf.jwks_uri ~= "" then
        return conf.jwks_uri
    end

    -- Resolve from discovery document
    if not conf.discovery or conf.discovery == "" then
        return nil, "no discovery or jwks_uri configured"
    end

    local now = ngx.time()
    local cached = _discovery_cache[conf.discovery]
    local ttl = conf.jwks_cache_ttl or 86400
    if cached and (now - cached.fetched_at) < ttl then
        return cached.jwks_uri
    end

    local httpc = http.new()
    httpc:set_timeout(5000)
    local res, err = httpc:request_uri(conf.discovery, { method = "GET", ssl_verify = false })
    if not res then
        return nil, "discovery fetch failed: " .. (err or "unknown")
    end
    if res.status ~= 200 then
        return nil, "discovery returned status " .. res.status
    end

    local doc, json_err = cjson.decode(res.body)
    if not doc then
        return nil, "discovery JSON parse failed: " .. (json_err or "unknown")
    end

    if not doc.jwks_uri or doc.jwks_uri == "" then
        return nil, "discovery document missing jwks_uri"
    end

    _discovery_cache[conf.discovery] = {
        jwks_uri = doc.jwks_uri,
        fetched_at = now,
    }
    core.log.info("[DPoP] Resolved jwks_uri from discovery: ", doc.jwks_uri)
    return doc.jwks_uri
end


local function fetch_jwks(uri)
    local httpc = http.new()
    httpc:set_timeout(5000)
    local res, err = httpc:request_uri(uri, { method = "GET", ssl_verify = false })
    if not res then
        return nil, "JWKS fetch failed: " .. (err or "unknown")
    end
    if res.status ~= 200 then
        return nil, "JWKS endpoint returned status " .. res.status
    end

    local jwks, json_err = cjson.decode(res.body)
    if not jwks or not jwks.keys then
        return nil, "JWKS JSON parse failed or missing keys: " .. (json_err or "unknown")
    end

    local keys_by_kid = {}
    for _, key in ipairs(jwks.keys) do
        if key.kid then
            keys_by_kid[key.kid] = key
        end
    end

    core.log.info("[DPoP] Fetched JWKS from ", uri, " — ", #jwks.keys, " key(s)")
    return keys_by_kid
end


local function get_jwk_for_kid(conf, kid)
    local jwks_uri, uri_err = resolve_jwks_uri(conf)
    if not jwks_uri then
        return nil, uri_err
    end

    local ttl = conf.jwks_cache_ttl or 86400
    local now = ngx.time()
    local cached = _jwks_cache[jwks_uri]

    -- Return from cache if valid and kid exists
    if cached and (now - cached.fetched_at) < ttl then
        if cached.keys_by_kid[kid] then
            return cached.keys_by_kid[kid]
        end
        -- kid miss — try refetch (key rotation), rate limited
    end

    -- Rate limit refetch: max once per 60s
    if (now - _jwks_last_refetch) < 60 and cached then
        -- Within rate limit window, return what we have
        if cached.keys_by_kid[kid] then
            return cached.keys_by_kid[kid]
        end
        return nil, "kid '" .. kid .. "' not found in JWKS (rate limited, retry later)"
    end

    local keys_by_kid, fetch_err = fetch_jwks(jwks_uri)
    if not keys_by_kid then
        return nil, fetch_err
    end

    _jwks_cache[jwks_uri] = {
        keys_by_kid = keys_by_kid,
        fetched_at = now,
    }
    _jwks_last_refetch = now

    if not keys_by_kid[kid] then
        return nil, "kid '" .. kid .. "' not found in JWKS"
    end

    return keys_by_kid[kid]
end

local ALG_TO_DIGEST = {
    RS256 = "sha256",
    RS384 = "sha384",
    RS512 = "sha512",
}

local function verify_access_token_signature(access_token, at_jwt, conf)
    local header = at_jwt.header

    -- 1. Check alg matches configured token_signing_algorithm
    local expected_alg = conf.token_signing_algorithm or "RS256"
    if header.alg ~= expected_alg then
        return false, "access token alg '"
            .. (header.alg or "nil")
            .. "' does not match expected '"
            .. expected_alg .. "'"
    end

    local digest = ALG_TO_DIGEST[header.alg]
    if not digest then
        return false, "unsupported token signing algorithm: " .. header.alg
    end

    -- 2. Get kid
    local kid = header.kid
    if not kid then
        return false, "access token header missing kid"
    end

    -- 3. Get JWK from JWKS
    local jwk, jwk_err = get_jwk_for_kid(conf, kid)
    if not jwk then
        return false, "JWKS lookup failed: " .. jwk_err
    end

    -- 4. Load public key from JWK (cached)
    local pkey, pkey_err = get_or_create_pkey(jwk)
    if not pkey then
        return false, "failed to load public key from JWK: " .. (pkey_err or "unknown")
    end

    -- 5. Verify signature (use raw_parts from parsed JWT)
    local signing_input = at_jwt.raw_parts[1] .. "." .. at_jwt.raw_parts[2]
    local signature = base64url_decode(at_jwt.raw_parts[3])
    if not signature then
        return false, "failed to decode access token signature"
    end

    local ok, err = pkey:verify(signature, signing_input, digest)
    if not ok then
        return false, "signature verification failed: " .. (err or "invalid signature")
    end

    return true
end

-- Convert raw ECDSA R||S (64 bytes for ES256) to DER format for OpenSSL
local function raw_ecdsa_to_der(raw_sig)
    if #raw_sig ~= 64 then
        return nil, "invalid ES256 signature length: expected 64, got " .. #raw_sig
    end

    local r = raw_sig:sub(1, 32)
    local s = raw_sig:sub(33, 64)

    -- Strip leading zeros but keep at least one byte
    while #r > 1 and r:byte(1) == 0 do r = r:sub(2) end
    while #s > 1 and s:byte(1) == 0 do s = s:sub(2) end

    -- Add leading zero if high bit set (DER integer must be positive)
    if r:byte(1) >= 128 then r = "\0" .. r end
    if s:byte(1) >= 128 then s = "\0" .. s end

    local r_der = "\x02" .. string.char(#r) .. r
    local s_der = "\x02" .. string.char(#s) .. s
    local seq = r_der .. s_der
    return "\x30" .. string.char(#seq) .. seq
end

-- DPoP Proof cryptographic signature verification (RFC §4.3 ¶1.4)
local function verify_dpop_proof_signature(proof)
    local signing_input = proof.raw_parts[1] .. "." .. proof.raw_parts[2]
    local signature = base64url_decode(proof.raw_parts[3])
    if not signature then
        return false, "failed to decode proof signature"
    end

    -- Load the proof's embedded JWK as a public key (cached)
    local pkey, pkey_err = get_or_create_pkey(proof.header.jwk)
    if not pkey then
        return false, "failed to load proof JWK as public key: " .. (pkey_err or "unknown")
    end

    local alg = proof.header.alg
    if alg == "ES256" then
        local der_sig, der_err = raw_ecdsa_to_der(signature)
        if not der_sig then
            return false, der_err
        end
        local ok, err = pkey:verify(der_sig, signing_input, "sha256")
        if not ok then
            return false, "ES256 proof signature verification failed: " .. (err or "invalid")
        end
    elseif alg == "RS256" then
        local ok, err = pkey:verify(signature, signing_input, "sha256")
        if not ok then
            return false, "RS256 proof signature verification failed: " .. (err or "invalid")
        end
    elseif alg == "RS384" then
        local ok, err = pkey:verify(signature, signing_input, "sha384")
        if not ok then
            return false, "RS384 proof signature verification failed: " .. (err or "invalid")
        end
    elseif alg == "RS512" then
        local ok, err = pkey:verify(signature, signing_input, "sha512")
        if not ok then
            return false, "RS512 proof signature verification failed: " .. (err or "invalid")
        end
    else
        return false, "unsupported proof signature algorithm: " .. alg
    end

    return true
end

-- Phase 3: Validate proof fields
local function validate_proof(proof, conf, method, request_uri)
    local h = proof.header
    local p = proof.payload

    -- 1. typ must be dpop+jwt
    if h.typ ~= "dpop+jwt" then
        return false, "typ must be dpop+jwt, got: " .. (h.typ or "nil")
    end

    -- 2. Explicit forbidden algorithm rejection (RFC §4.3 ¶1.2, §11.6)
    if h.alg == "none" then
        return false, "[§11.6] 'none' algorithm forbidden"
    end
    if h.alg:sub(1, 2) == "HS" then
        return false, "[§11.6] symmetric algorithms (HS*) forbidden"
    end

    -- alg must be in allowed_algorithms
    local alg_allowed = false
    for _, allowed in ipairs(conf.allowed_algs or {"ES256"}) do
        if h.alg == allowed then
            alg_allowed = true
            break
        end
    end
    if not alg_allowed then
        return false, "alg not allowed: " .. (h.alg or "nil")
    end

    -- 3. jwk must be present, must not contain private key (d)
    if not h.jwk then
        return false, "jwk missing from proof header"
    end
    if h.jwk.d then
        return false, "jwk contains private key material (d)"
    end

    -- 4. htm must match request method
    if not p.htm then
        return false, "htm claim missing"
    end
    if p.htm:upper() ~= method:upper() then
        return false, "htm mismatch: proof=" .. p.htm .. ", request=" .. method
    end

    -- 5. htu path match
    if not p.htu then
        return false, "htu claim missing"
    end
    -- Strip query string from request URI for comparison
    local req_path = request_uri:match("^([^%?#]*)") or request_uri
    if conf.strict_htu then
        -- Full URL comparison: public_base_url + request_path == htu
        local expected_htu = (conf.public_base_url or "") .. req_path
        if p.htu ~= expected_htu then
            return false, "htu mismatch (strict): proof=" .. p.htu .. ", expected=" .. expected_htu
        end
    else
        -- Path-only comparison
        local proof_path = extract_path(p.htu)
        if proof_path ~= req_path then
            return false, "htu path mismatch: proof_path="
                .. proof_path .. ", request_path=" .. req_path
        end
    end

    -- 6. iat freshness check (proof_max_age + clock_skew_seconds tolerance)
    if not p.iat then
        return false, "iat claim missing"
    end
    local now = ngx.time()
    local age = now - p.iat
    local skew = conf.clock_skew_seconds or 5
    local max_age = (conf.proof_max_age or 120) + skew
    if age > max_age then
        return false, "proof too old: age=" .. age .. "s, max=" .. max_age .. "s"
    end
    if age < -skew then
        return false, "proof from the future: age=" .. age .. "s"
    end

    -- 7. jti must be present
    if not p.jti or p.jti == "" then
        return false, "jti claim missing"
    end

    return true
end

-- JTI replay check: memory (ngx.shared → local table) implementation
local function jti_check_memory(jti, ttl)
    -- Priority 1: ngx.shared dict (shared across workers, single pod)
    local jti_cache = ngx.shared.dpop_jti_cache
    if jti_cache then
        if jti_cache:get(jti) then return false end
        local ok, set_err = jti_cache:set(jti, true, ttl)
        if not ok then
            core.log.warn("[DPoP] Failed to store jti in shared dict: ", set_err)
        end
        return true
    end

    -- Priority 2: module-level table (per-worker, not distributed)
    core.log.info("[DPoP] Using module-level local JTI cache (no shared dict configured)")
    if _jti_local_count > 1000 then
        jti_local_cleanup()
    end
    local now = ngx.time()
    if _jti_local_cache[jti] and _jti_local_cache[jti] > now then
        return false
    end
    _jti_local_cache[jti] = now + ttl
    _jti_local_count = _jti_local_count + 1
    return true
end

-- Execute fallback strategy when a distributed cache fails
-- Returns: ok (bool), err_reason (string or nil)
--   ok=true  → request may proceed (bypass or memory check passed)
--   ok=false → request must be rejected
--   err_reason="cache_unavailable" → caller should return HTTP 503
local function jti_fallback(fallback, jti, ttl)
    if fallback == "reject" then
        core.log.warn("[DPoP] Replay cache fallback=reject — denying request")
        return false, "cache_unavailable"
    end
    if fallback == "bypass" then
        core.log.warn("[DPoP] Replay cache fallback=bypass",
            " — allowing request without replay check")
        return true
    end
    -- fallback == "memory" (default)
    core.log.warn("[DPoP] Replay cache fallback=memory — using local replay check")
    return jti_check_memory(jti, ttl)
end

-- JTI replay check: dispatches to ispn, redis, or memory based on replay_cache.type
local function jti_check(jti, conf)
    local rc = conf.replay_cache or {}
    local cache_type = rc.type or "memory"
    local fallback = rc.fallback or "memory"
    local ttl = rc.ttl or conf.proof_max_age or 120

    -- ===== Infinispan =====
    if cache_type == "ispn" then
        -- L1: fast local check before network call
        if not jti_check_memory(jti, ttl) then
            core.log.warn("[DPoP] JTI replay detected (L1 local cache, before Infinispan): ", jti)
            return false
        end
        local ispn = rc.ispn or {}
        if not ispn.endpoint or ispn.endpoint == "" then
            core.log.warn("[DPoP] replay_cache.type=ispn but no endpoint configured")
            return jti_fallback(fallback, jti, ttl)
        end
        local cache_name = ispn.cache_name or "dpop-jti"
        local has_creds = ispn.username and ispn.username ~= ""
            and ispn.password and ispn.password ~= ""
        local url = ispn.endpoint .. "/rest/v2/caches/" .. cache_name .. "/" .. jti
        local uri_path = url:match("https?://[^/]+(/.*)") or "/"

        local httpc = http.new()
        httpc:set_timeout(3000)
        local headers = {
            ["Content-Type"] = "text/plain",
            ["timeToLiveSeconds"] = tostring(ttl),
        }
        -- Try cached digest nonce first, fall back to no-auth initial request
        if has_creds and _ispn_digest_cache[ispn.endpoint] then
            local cached = _ispn_digest_cache[ispn.endpoint]
            local auth_hdr = ispn_digest_auth(
                'realm="' .. (cached.realm or "")
                    .. '", nonce="' .. cached.nonce
                    .. '", qop="' .. (cached.qop or "auth") .. '"',
                "POST", uri_path, ispn.username, ispn.password
            )
            if auth_hdr then headers["Authorization"] = auth_hdr end
        end
        local res, err = httpc:request_uri(url,
            { method = "POST", body = "1", headers = headers, ssl_verify = false }
        )
        -- Digest auth: on 401, parse nonce from WWW-Authenticate and retry
        if res and res.status == 401 and has_creds then
            local www_auth = res.headers
                and (res.headers["WWW-Authenticate"]
                    or res.headers["www-authenticate"])
            if www_auth and www_auth:lower():find("digest") then
                local auth_hdr, nonce, realm, qop = ispn_digest_auth(
                    www_auth, "POST", uri_path, ispn.username, ispn.password
                )
                if auth_hdr then
                    -- Cache nonce for subsequent requests
                    _ispn_digest_cache[ispn.endpoint] = {
                        nonce = nonce, realm = realm,
                        qop = qop or "auth",
                    }
                    headers["Authorization"] = auth_hdr
                    httpc = http.new()
                    httpc:set_timeout(3000)
                    res, err = httpc:request_uri(url,
                        { method = "POST", body = "1", headers = headers, ssl_verify = false }
                    )
                end
            end
        end
        if res then
            if res.status == 409 then
                core.log.warn("[DPoP] JTI replay detected (distributed/Infinispan): ", jti)
                return false
            end
            if res.status == 204 or res.status == 200 then
                core.log.info("[DPoP] JTI stored in Infinispan (no replay)")
                return true
            end
            -- Nonce expired: clear cache so next request gets fresh nonce
            if res.status == 401 and has_creds then
                _ispn_digest_cache[ispn.endpoint] = nil
            end
            core.log.warn("[DPoP] Infinispan unexpected status ",
                res.status, " — triggering fallback")
        else
            core.log.warn("[DPoP] Infinispan request failed: ", err, " — triggering fallback")
        end
        return jti_fallback(fallback, jti, ttl)
    end

    -- ===== Redis =====
    if cache_type == "redis" then
        -- L1: fast local check before network call
        if not jti_check_memory(jti, ttl) then
            core.log.warn("[DPoP] JTI replay detected (L1 local cache, before Redis): ", jti)
            return false
        end
        local redis_conf = rc.redis or {}
        if not redis_conf.host or redis_conf.host == "" then
            core.log.warn("[DPoP] replay_cache.type=redis but no host configured")
            return jti_fallback(fallback, jti, ttl)
        end
        local redis = require("resty.redis")
        local red = redis:new()
        red:set_timeout(redis_conf.timeout or 2000)
        local ok, err = red:connect(redis_conf.host, redis_conf.port or 6379)
        if not ok then
            core.log.warn("[DPoP] Redis connect failed: ", err, " — triggering fallback")
            return jti_fallback(fallback, jti, ttl)
        end
        if redis_conf.password and redis_conf.password ~= "" then
            local auth_ok, auth_err = red:auth(redis_conf.password)
            if not auth_ok then
                core.log.warn("[DPoP] Redis auth failed: ", auth_err, " — triggering fallback")
                red:close()
                return jti_fallback(fallback, jti, ttl)
            end
        end
        -- SET dpop:jti:<jti> 1 EX ttl NX — atomic check-and-set
        local redis_key = "dpop:jti:" .. jti
        local res, err = red:set(redis_key, "1", "EX", ttl, "NX")
        if not res then
            core.log.warn("[DPoP] Redis SET failed: ", err, " — triggering fallback")
            red:set_keepalive(10000, 100)
            return jti_fallback(fallback, jti, ttl)
        end
        red:set_keepalive(10000, 100)
        if res == ngx.null then
            -- Key already existed → replay
            core.log.warn("[DPoP] JTI replay detected (Redis): ", jti)
            return false
        end
        core.log.info("[DPoP] JTI stored in Redis (no replay)")
        return true
    end

    -- ===== Memory (default) =====
    return jti_check_memory(jti, ttl)
end

-- ===========================================================================
-- Introspection (RFC 7662) — fallback for opaque tokens without cnf.jkt
-- ===========================================================================

local function get_introspection_cache_key(access_token)
    local sha = resty_sha256:new()
    sha:update(access_token)
    return ngx.encode_base64(sha:final())
end


local function call_introspection(access_token, conf)
    -- Check cache first (shared dict → local fallback)
    local cache_ttl = conf.introspection_cache_ttl or 0
    if cache_ttl > 0 then
        local cache_key = get_introspection_cache_key(access_token)

        -- Priority 1: ngx.shared dict (cross-worker, TTL-managed)
        local intro_shdict = ngx.shared.dpop_intro_cache
        if intro_shdict then
            local cached_jkt = intro_shdict:get(cache_key)
            if cached_jkt then
                core.log.info("[DPoP] Introspection cache HIT (shared dict)")
                return { active = true, cnf = { jkt = cached_jkt } }
            end
        else
            -- Priority 2: module-level local table (per-worker)
            local cached = _introspection_cache[cache_key]
            if cached and (ngx.now() - cached.cached_at) < cache_ttl then
                core.log.info("[DPoP] Introspection cache HIT (local)")
                return { active = true, cnf = { jkt = cached.cnf_jkt } }
            end
        end
    end

    -- Cache miss or disabled — make HTTP call
    local httpc = http.new()
    httpc:set_timeout(5000)
    local body = "token=" .. access_token .. "&token_type_hint=access_token"
    local req_headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
    }
    if conf.introspection_client_id and conf.introspection_client_id ~= ""
       and conf.introspection_client_secret and conf.introspection_client_secret ~= "" then
        req_headers["Authorization"] = "Basic " .. ngx.encode_base64(
            conf.introspection_client_id .. ":" .. conf.introspection_client_secret
        )
    end
    local res, err = httpc:request_uri(conf.introspection_endpoint, {
        method = "POST",
        body = body,
        headers = req_headers,
        ssl_verify = false,
    })
    if not res then
        return nil, "introspection request failed: " .. (err or "unknown")
    end
    if res.status ~= 200 then
        return nil, "introspection returned status " .. res.status
    end
    local result, json_err = cjson.decode(res.body)
    if not result then
        return nil, "introspection response parse error: " .. (json_err or "unknown")
    end

    -- Cache successful result (active + cnf.jkt)
    if cache_ttl > 0 and result.active and result.cnf and result.cnf.jkt then
        local cache_key = get_introspection_cache_key(access_token)

        -- Priority 1: ngx.shared dict (cross-worker, TTL-managed automatically)
        local intro_shdict = ngx.shared.dpop_intro_cache
        if intro_shdict then
            local ok, set_err = intro_shdict:set(cache_key, result.cnf.jkt, cache_ttl)
            if not ok then
                core.log.warn("[DPoP] Failed to store introspection in shared dict: ", set_err)
            end
        else
            -- Priority 2: module-level local table (per-worker)
            _introspection_cache[cache_key] = {
                cnf_jkt = result.cnf.jkt,
                cached_at = ngx.now(),
            }
            _introspection_cache_count = _introspection_cache_count + 1
            if _introspection_cache_count > 1000 then
                local now = ngx.now()
                for k, v in pairs(_introspection_cache) do
                    if (now - v.cached_at) >= cache_ttl then
                        _introspection_cache[k] = nil
                        _introspection_cache_count = _introspection_cache_count - 1
                    end
                end
            end
        end
        core.log.info("[DPoP] Introspection result cached (TTL=", cache_ttl, "s)")
    end

    return result
end

-- ===========================================================================
-- rewrite()
-- Runs in rewrite phase (priority 2600) so that DPoP → Bearer conversion
-- happens BEFORE openid-connect (priority 2599) verifies the Bearer token.
-- ===========================================================================

function _M.rewrite(conf, ctx)
    local method = core.request.get_method()
    local request_uri = ctx.var.request_uri
    local headers = core.request.headers(ctx)

    local auth_header = headers["authorization"]
    local dpop_header = headers["dpop"]

    core.log.info("[DPoP] Request: ", method, " ", request_uri,
        " | Authorization present: ", auth_header and "yes" or "no",
        " | DPoP header present: ", dpop_header and "yes" or "no")

    -- ===== uri_allow: skip DPoP for non-matching paths =====
    local enforce = conf.uri_allow
    if enforce and #enforce > 0 then
        local match_path = request_uri:match("^([^%?#]*)") or request_uri
        local matched = false
        for _, p in ipairs(enforce) do
            if p:sub(-1) == "*" then
                -- Prefix match: /api/* matches /api/anything
                local prefix = p:sub(1, -2)
                if match_path:sub(1, #prefix) == prefix then
                    matched = true
                    break
                end
            else
                -- Exact match: /api/users matches only /api/users
                if match_path == p then
                    matched = true
                    break
                end
            end
        end
        if not matched then
            core.log.info("[DPoP] Path not in uri_allow, skipping DPoP validation: ", request_uri)
            return
        end
    end

    -- Reject multiple DPoP headers (RFC §4.1 ¶2)
    if type(dpop_header) == "table" then
        core.log.warn("[DPoP] Multiple DPoP headers detected")
        return dpop_error("invalid_dpop_proof", "multiple DPoP headers")
    end

    -- Reject if no Authorization header (DPoP plugin is active → auth required)
    if not auth_header then
        core.log.warn("[DPoP] No Authorization header on DPoP-protected route")
        dpop_audit("deny", "invalid_dpop_proof",
            "missing authorization header",
            method, request_uri, nil, nil, nil)
        return dpop_error("invalid_dpop_proof", "missing authorization header")
    end

    local auth_lower = auth_header:lower()
    if auth_lower:sub(1, 5) ~= "dpop " then
        -- ===== D1: Bearer Downgrade Detection (RFC 9449 §11.7) =====
        -- If scheme is Bearer, check if the token contains cnf.jkt.
        -- A DPoP-bound token sent as Bearer is a downgrade attack.
        if auth_lower:sub(1, 7) == "bearer " then
            local bearer_token = auth_header:sub(8)
            if bearer_token and bearer_token ~= "" then
                local bt_jwt, _ = parse_jwt(bearer_token)
                if bt_jwt and bt_jwt.payload and bt_jwt.payload.cnf
                    and bt_jwt.payload.cnf.jkt then
                    core.log.warn("[DPoP] D1: Bearer downgrade detected — ",
                        "token has cnf.jkt=", bt_jwt.payload.cnf.jkt,
                        " but sent as Bearer scheme")
                    dpop_audit("deny", "DPOP_DOWNGRADE_DETECTED",
                        "bearer downgrade detected",
                        method, request_uri, nil, nil, nil)
                    return dpop_error("DPOP_DOWNGRADE_DETECTED",
                        "DPoP-bound token used with Bearer scheme")
                end
                -- Bearer token without cnf.jkt → not DPoP-bound, reject
                core.log.warn("[DPoP] Bearer token without cnf.jkt on DPoP-protected route")
                dpop_audit("deny", "invalid_dpop_proof",
                    "bearer token not DPoP-bound",
                    method, request_uri, nil, nil, nil)
                return dpop_error("invalid_dpop_proof", "DPoP scheme required")
            end
        end
        -- Non-DPoP, non-Bearer scheme → reject
        core.log.warn("[DPoP] Unsupported authorization scheme on DPoP-protected route")
        dpop_audit("deny", "invalid_dpop_proof",
            "unsupported authorization scheme",
            method, request_uri, nil, nil, nil)
        return dpop_error("invalid_dpop_proof", "DPoP scheme required")
    end

    -- Extract access token from "DPoP <token>"
    local access_token = auth_header:sub(6)
    if not access_token or access_token == "" then
        core.log.warn("[DPoP] Authorization header has DPoP scheme but no token")
        return dpop_error("invalid_dpop_proof", "missing access token")
    end
    -- DPoP proof header required when using DPoP scheme
    if not dpop_header or dpop_header == "" then
        core.log.warn("[DPoP] DPoP scheme used but no DPoP proof header")
        return dpop_error("invalid_dpop_proof", "missing DPoP proof header")
    end

    -- ===== Phase 2: Parse DPoP proof JWT =====
    local proof, err = parse_jwt(dpop_header)
    if not proof then
        core.log.warn("[DPoP] Failed to parse DPoP proof: ", err)
        return dpop_error("invalid_dpop_proof", err)
    end

    core.log.info("[DPoP] Proof parsed - typ: ", proof.header.typ,
        " | alg: ", proof.header.alg,
        " | jwk.kty: ", proof.header.jwk and proof.header.jwk.kty or "nil",
        " | htm: ", proof.payload.htm,
        " | htu: ", proof.payload.htu,
        " | jti: ", proof.payload.jti,
        " | iat: ", proof.payload.iat)

    -- ===== Phase 2.5: DPoP Proof Cryptographic Signature Verification (RFC §4.3 ¶1.4) =====
    local proof_sig_ok, proof_sig_err = verify_dpop_proof_signature(proof)
    if not proof_sig_ok then
        core.log.warn("[DPoP] Proof signature verification failed: ", proof_sig_err)
        dpop_audit("deny", "invalid_dpop_proof",
            "proof signature invalid",
            method, request_uri, proof.payload.jti, nil, nil)
        return dpop_error("invalid_dpop_proof", "proof signature invalid")
    end
    core.log.info("[DPoP] Phase 2.5 PASS: Proof cryptographic signature verified")

    -- ===== Phase 3: Validate proof =====
    local valid, val_err = validate_proof(proof, conf, method, request_uri)
    if not valid then
        core.log.warn("[DPoP] Proof validation failed: ", val_err)
        dpop_audit("deny", "invalid_dpop_proof", val_err,
            method, request_uri, proof.payload.jti, nil, nil)
        return dpop_error("invalid_dpop_proof", val_err)
    end
    core.log.info("[DPoP] Phase 3 PASS: All proof field validations passed")

    -- ===== Phase 5: JTI Replay Protection =====
    local jti = proof.payload.jti
    local jti_unique, jti_err = jti_check(jti, conf)
    if not jti_unique then
        if jti_err == "cache_unavailable" then
            core.log.warn("[DPoP] Replay cache unavailable, fallback=reject")
            dpop_audit("deny", "server_error",
                "replay cache unavailable",
                method, request_uri, jti, nil, nil)
            return 503, { error = "server_error", error_description = "replay cache unavailable" }
        end
        core.log.warn("[DPoP] JTI replay detected: ", jti)
        dpop_audit("deny", "invalid_dpop_proof",
            "jti replay detected",
            method, request_uri, jti, nil, nil)
        return dpop_error("invalid_dpop_proof", "jti replay detected")
    end
    core.log.info("[DPoP] Phase 5 PASS: JTI replay check passed (jti=", jti, ")")

    -- ===== ath Claim Validation (RFC §4.3 ¶1 item 10) =====
    if not proof.payload.ath or proof.payload.ath == "" then
        core.log.warn("[DPoP] ath claim missing from proof")
        return dpop_error("invalid_dpop_proof", "ath claim missing")
    end
    local expected_ath = sha256_b64url(access_token)
    if proof.payload.ath ~= expected_ath then
        core.log.warn("[DPoP] ath mismatch: computed=", expected_ath, " proof=", proof.payload.ath)
        return dpop_error("invalid_dpop_proof", "ath mismatch")
    end
    core.log.info("[DPoP] ath validation PASS")

    -- ===== Access Token Signature Verification + Phase 4: Binding Validation =====
    local enforce_intro = conf.enforce_introspection or false
    local expected_thumbprint
    local issuer, client_id

    if enforce_intro then
        -- enforce_introspection=true: skip JWT parsing, go directly to introspection
        if not conf.introspection_endpoint or conf.introspection_endpoint == "" then
            return dpop_error("server_error",
                "enforce_introspection requires introspection_endpoint")
        end
        core.log.info("[DPoP] enforce_introspection=true",
            " — skipping token signature verification,",
            " calling introspection")
        local intro_result, intro_err = call_introspection(access_token, conf)
        if not intro_result then
            return dpop_error("invalid_token", "introspection failed: " .. (intro_err or "unknown"))
        end
        if not intro_result.active then
            return dpop_error("invalid_token", "token is not active (revoked or expired)")
        end
        if intro_result.cnf and intro_result.cnf.jkt then
            expected_thumbprint = intro_result.cnf.jkt
        else
            return dpop_error("invalid_token", "introspection response missing cnf.jkt")
        end
        -- Token claim extraction from introspection result
        issuer = intro_result.iss
        client_id = intro_result.azp or intro_result.client_id
    else
        -- Parse token once, reuse for both sig verify and cnf.jkt extraction
        local at_jwt, at_err = parse_jwt(access_token)

        -- Token signature verification (uses pre-parsed JWT)
        local verify_at = conf.verify_access_token
        if verify_at == nil then verify_at = true end
        local has_jwks = (conf.discovery and conf.discovery ~= "")
            or (conf.jwks_uri and conf.jwks_uri ~= "")
        if has_jwks and verify_at then
            if not at_jwt then
                dpop_audit("deny", "invalid_token",
                    "access token parse failed",
                    method, request_uri,
                    proof.payload.jti, nil, nil)
                return dpop_error("invalid_token",
                    "failed to parse access token: "
                    .. (at_err or "unknown"))
            end
            local sig_ok, sig_err = verify_access_token_signature(access_token, at_jwt, conf)
            if not sig_ok then
                core.log.warn("[DPoP] Access token signature verification failed: ", sig_err)
                dpop_audit("deny", "invalid_token",
                    "access token signature failed",
                    method, request_uri,
                    proof.payload.jti, nil, nil)
                return dpop_error("invalid_token", "access token signature verification failed")
            end
            core.log.info("[DPoP] Access token signature verification PASS")
        end

        -- cnf.jkt extraction from pre-parsed JWT
        if at_jwt and at_jwt.payload.cnf and at_jwt.payload.cnf.jkt then
            expected_thumbprint = at_jwt.payload.cnf.jkt
            core.log.info("[DPoP] cnf.jkt extracted from JWT access token")
        end

        -- Token claim extraction from JWT
        if at_jwt and at_jwt.payload then
            issuer = at_jwt.payload.iss
            client_id = at_jwt.payload.azp or at_jwt.payload.client_id
        end

        if not expected_thumbprint then
            local has_introspection = conf.introspection_endpoint
                and conf.introspection_endpoint ~= ""
            if has_introspection then
                core.log.info("[DPoP] cnf.jkt not in JWT — calling introspection endpoint")
                local intro_result, intro_err = call_introspection(access_token, conf)
                if not intro_result then
                    core.log.warn("[DPoP] Introspection failed: ", intro_err)
                    return dpop_error("invalid_token", "introspection failed: " .. intro_err)
                end
                if not intro_result.active then
                    return dpop_error("invalid_token", "token is not active (introspection)")
                end
                if intro_result.cnf and intro_result.cnf.jkt then
                    expected_thumbprint = intro_result.cnf.jkt
                    core.log.info("[DPoP] cnf.jkt extracted from introspection response")
                else
                    return dpop_error("invalid_token", "introspection response missing cnf.jkt")
                end
                -- Override token claims from introspection (more authoritative)
                issuer = intro_result.iss or issuer
                client_id = intro_result.azp or intro_result.client_id or client_id
            else
                -- No introspection configured, return original error
                if not at_jwt then
                    return dpop_error("invalid_dpop_proof",
                        "failed to parse access token: "
                        .. (at_err or "unknown"))
                end
                return dpop_error("invalid_dpop_proof", "access token missing cnf.jkt claim")
            end
        end
    end

    -- ===== Issuer Validation =====
    if conf.token_issuer and conf.token_issuer ~= "" then
        if issuer ~= conf.token_issuer then
            core.log.warn("[DPoP] Issuer mismatch: got=", issuer, " expected=", conf.token_issuer)
            dpop_audit("deny", "invalid_token",
                "issuer mismatch", method, request_uri,
                proof.payload.jti, issuer, client_id)
            return dpop_error("invalid_token", "issuer mismatch")
        end
        core.log.info("[DPoP] Issuer validation PASS: ", issuer)
    end

    -- Compute JWK Thumbprint from proof's jwk
    local computed_thumbprint, tp_err = compute_jwk_thumbprint(proof.header.jwk)
    if not computed_thumbprint then
        core.log.warn("[DPoP] Failed to compute JWK thumbprint: ", tp_err)
        return dpop_error("invalid_dpop_proof", "failed to compute jwk thumbprint: " .. tp_err)
    end
    -- Compare thumbprints
    if computed_thumbprint ~= expected_thumbprint then
        core.log.warn("[DPoP] Binding mismatch: computed=", computed_thumbprint,
            " expected=", expected_thumbprint)
        dpop_audit("deny", "DPOP_BINDING_MISMATCH",
            "cnf.jkt binding mismatch",
            method, request_uri,
            proof.payload.jti, issuer, client_id)
        return dpop_error("DPOP_BINDING_MISMATCH", "cnf.jkt binding mismatch")
    end
    core.log.info("[DPoP] Phase 4 PASS: cnf.jkt binding match confirmed")

    -- ===== Header Conversion: DPoP → Bearer =====
    core.request.set_header(ctx, "Authorization", "Bearer " .. access_token)

    -- Remove DPoP proof header before forwarding to backend
    core.request.set_header(ctx, "DPoP", nil)

    -- Add DPoP-Thumbprint header
    if conf.send_thumbprint_header then
        core.request.set_header(ctx, "DPoP-Thumbprint", computed_thumbprint)
    end

    core.log.info("[DPoP] ALL PHASES PASSED - request proceeding with Bearer token")
    dpop_audit("allow", nil, nil, method, request_uri, proof.payload.jti, issuer, client_id)
    return
end

return _M
