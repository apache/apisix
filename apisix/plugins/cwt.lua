local core              = require("apisix.core")
local consumer_mod      = require("apisix.consumer")
local cjson             = require("cjson.safe")
local resty_string      = require("resty.string")
local openssl_digest    = require("resty.openssl.digest")
local openssl_pkey      = require("resty.openssl.pkey")
local codec             = require("apisix.plugins.cwt.codec")
local keccak            = require("apisix.plugins.cwt.keccak")
require("resty.openssl")

local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local cjson_encode      = cjson.encode
local cjson_decode      = cjson.decode
local ngx_time          = ngx.time
local plugin_name       = "cwt"

local str_const = {
    chain_ethereum = "ethereum",
    chain_jingtum = "jingtum",
    chain_bitcoin = "bitcoin",
    chain_ripple = "ripple",
    raw_underline = "raw_",
    table  = "table",
    plus = "+",
    dash = "-",
    slash = "/",
    underline = "_",
    equal = "=",
    empty = "",

    invalid_cwt = "invalid cwt string",
    cwt_join_msg = "%s.%s",
    regex_join_separator = "([^%s]+)",
    regex_split_dot = "%.",
    header = "header",
    type = "type",
    CWT = "CWT",
    alg = "alg",
    chain = "chain",
    payload = "payload",
    time = "time",
    signature = "signature",
    reason = "reason",
    verified = "verified",
    valid = "valid",
    verified_ok = "verified ok",
}

local schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            default = "cwt_auth"
        },
        cookie = {
            type = "string",
            default = "cwt_auth"
        },
        query = {
            type = "string",
            default = "cwt"
        },
        hide_credentials = {
            type = "boolean",
            default = true
        }
    },
}

local consumer_schema = {
    type = "object",
    properties = {
        usr = {type = "string"},
        wallet = {type = "string"},
        exp = {type = "integer", minimum = 1}
    },
    required = {"usr", "wallet", "exp"},
}


local _M = {
    version = 0.1,
    priority = 1,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema
}


function _M.check_schema(conf, schema_type)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    local ok, err
    if schema_type == core.schema.TYPE_CONSUMER then
        ok, err = core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end

    if not ok then
        return false, err
    end

    return true
end

local function remove_cwt_cookie(src, key)
    local cookie_key_pattern = "([a-zA-Z0-9-_]*)"
    local cookie_val_pattern = "([a-zA-Z0-9-._]*)"
    local t = table.new(1, 0)

    local it, err = ngx.re.gmatch(src, cookie_key_pattern .. "=" .. cookie_val_pattern, "jo")
    if not it then
        core.log.error("match origins failed: ", err)
        return src
    end
    while true do
        local m, err = it()
        if err then
            core.log.error("iterate origins failed: ", err)
            return src
        end
        if not m then
            break
        end
        if m[1] ~= key then
            table.insert(t, m[0])
        end
    end

    return table.concat(t, "; ")
end

local function fetch_cwt_token(conf, ctx)
    -- first, fetch from header
    local token = core.request.header(ctx, conf.header)
    if token then
        if conf.hide_credentials then
            core.request.set_header(ctx, conf.header, nil)
        end

        local prefix = string.sub(token, 1, 7)
        if prefix == 'Bearer ' or prefix == 'bearer ' then
            return string.sub(token, 8)
        end

        return token
    end
    -- second, fetch from query arg
    local uri_args = core.request.get_uri_args(ctx) or {}
    token = uri_args[conf.query]
    if token then
        if conf.hide_credentials then
            uri_args[conf.query] = nil
            core.request.set_uri_args(ctx, uri_args)
        end
        return token
    end
    -- third, fetch from cookie
    local val = ctx.var["cookie_" .. conf.cookie]
    if val then
        if conf.hide_credentials then
            -- hide for cookie
            local src = core.request.header(ctx, "Cookie")
            local reset_val = remove_cwt_cookie(src, conf.cookie)
            core.request.set_header(ctx, "Cookie", reset_val)
        end
        return val
    end

    return nil, "Missing token"
end

local function cwt_encode(field)
    if type(field) == str_const.table then
        field = cjson_encode(field)
    end
    local res = ngx_encode_base64(field):gsub(str_const.plus, str_const.dash):gsub(str_const.slash, str_const.underline):gsub(str_const.equal, str_const.empty)
    return res
end

local function cwt_decode(b64_str, json_decode)
    b64_str = b64_str:gsub(str_const.dash, str_const.plus):gsub(str_const.underline, str_const.slash)

    local reminder = #b64_str % 4
    if reminder > 0 then
        b64_str = b64_str .. string.rep(str_const.equal, 4 - reminder)
    end
    local data = ngx_decode_base64(b64_str)
    if not data then
        return nil
    end
    if json_decode then
        data = cjson_decode(data)
    end
    return data
end

local function parse_cwt(encoded_header, encoded_payload, signature)
    local header = cwt_decode(encoded_header, true)
    if not header then
        return nil, "invalid header: " .. encoded_header
    end

    local payload = cwt_decode(encoded_payload, true)
    if not payload then
        return nil, "invalid payload: " .. encoded_payload
    end

    local basic_cwt = {
        type = str_const.CWT,
        raw_header = encoded_header,
        raw_payload = encoded_payload,
        header = header,
        payload = payload,
        signature = signature
    }
    return basic_cwt
end

local function split_string(str, separator)
    local result = {}
    local sep = string.format(str_const.regex_join_separator, separator)
    for m in str:gmatch(sep) do
        result[#result+1] = m
    end
    return result
end

local function load_cwt(cwt_str)
    local tokens = split_string(cwt_str, str_const.regex_split_dot)
    local num_tokens = #tokens
    if num_tokens == 3 then
        local cwt_obj, err = parse_cwt(tokens[1], tokens[2], tokens[3])
        if not cwt_obj then
            return {
                valid = false,
                verified = false,
                reason = err
            }
        end
        cwt_obj[str_const.verified] = false
        cwt_obj[str_const.valid] = true
        return cwt_obj
    else
        return {
            valid = false,
            verified = false,
            reason = str_const.invalid_cwt
        }
    end
end

local function verify_ethereum_cwt(public_key_pem, message, signature, address, alg)
    local pk, err = openssl_pkey.new(public_key_pem, {format = "PEM"})
    if not pk then
        return false, "Failed to load public key: ".. err
    end
    local public_key_bin
    if alg == "secp256k1" then
        local digest, err = openssl_digest.new("sha256")
        if not digest then
            return false, "Failed to new digest.sha256: " .. err
        end
        local ok, err = digest:update(message)
        if not ok then
            return false, "Failed to update digest: " .. err
        end
        local ok, err = pk:verify(signature, digest)
        if not ok then
            return false, "Failed to verify signature: " .. err
        end
        local parameters, err = pk:get_parameters()
        if not parameters then
            return false, "Failed to get parameters: " .. err
        end
        local x_bin = parameters.x:to_binary()
        local y_bin = parameters.y:to_binary()
        if not x_bin or not y_bin then
            return false, "Failed to get x/y coordinate of the public key"
        end
        public_key_bin = (x_bin .. y_bin)
    else
        return false, "Unsupported algorithm: " .. alg
    end
    local keccak_hash, err = keccak.keccak256(public_key_bin)
    if not keccak_hash then
        return false, "Failed to get keccak256 hash: " .. err
    end
    local hash_last20 = string.sub(keccak_hash, -20)
    local wallet_address = resty_string.to_hex(hash_last20)
    address = address:gsub("^0x", "")
    if wallet_address ~= address then
        return false, "Wallet address mismatch"
    end
    return true
end

local function isEven(n)
    return (n % 2) == 0
end

local function get_public_key_from_xy(bn_x, bn_y)
    local last_byte = string.byte(bn_y:to_binary(), -1)
    if isEven(last_byte) then
        return string.char(0x02) .. bn_x:to_binary()
    else
        return string.char(0x03) .. bn_x:to_binary()
    end
end

local function derive_address_from_pubkey(public_key, chain)
    local digest_inner, err = openssl_digest.new("sha256")
    if not digest_inner then
        return nil, "Failed to new digest.sha256: " .. err
    end
    local digest_outer, err = openssl_digest.new("rmd160")
    if not digest_outer then
        return nil, "Failed to new digest.ripemd160: " .. err
    end
    local account_id = digest_outer:final(digest_inner:final(public_key))
    local payload = string.char(0x00) .. account_id
    local digest_check1, err = openssl_digest.new("sha256")
    if not digest_check1 then
        return nil, "Failed to new digest.sha256: " .. err
    end
    local digest_check2, err = openssl_digest.new("sha256")
    if not digest_check2 then
        return nil, "Failed to new digest.sha256: " .. err
    end
    local check_sum = digest_check2:final(digest_check1:final(payload)):sub(1, 4)
    local data_to_encode = payload .. check_sum
    if chain == str_const.chain_jingtum then
        return codec.base58jingtum:encode(data_to_encode)
    elseif chain == str_const.chain_ripple then
        return codec.base58ripple:encode(data_to_encode)
    elseif chain == str_const.chain_bitcoin then
        return codec.base58bitcoin:encode(data_to_encode)
    else
        return nil, "Unsupported chain: " .. chain
    end
end

local function verify_ripple_cwt(public_key_pem, message, signature, address, alg, chain)
    local pk, err = openssl_pkey.new(public_key_pem, {format = "PEM"})
    if not pk then
        return false, "Failed to load public key: ".. err
    end
    local public_key
    if alg == "secp256k1" then
        local digest, err = openssl_digest.new("sha256")
        if not digest then
            return false, "Failed to new digest.sha256: " .. err
        end
        local ok, err = digest:update(message)
        if not ok then
            return false, "Failed to update digest: " .. err
        end
        local ok, err = pk:verify(signature, digest)
        if not ok then
            return false, "Failed to verify signature: " .. err
        end
        local parameters, err = pk:get_parameters()
        if not parameters then
            return false, "Failed to get parameters: " .. err
        end
        public_key = get_public_key_from_xy(parameters.x, parameters.y)
        if not public_key then
            return false, "Failed to get the public key"
        end
    elseif alg == "ed25519" then
        local ok, err = pk:verify(signature, message)
        if not ok then
            return false, "Failed to verify signature: " .. err
        end
        local parameters, err = pk:get_parameters()
        if not parameters then
            return false, "Failed to get parameters: " .. err
        end
        public_key = string.char(0xed) .. parameters.public
    else
        return false, "Unsupported algorithm: " .. alg
    end
    local wallet_address, err = derive_address_from_pubkey(public_key, chain)
    if not wallet_address then
        return false, "Failed to derive wallet address: " .. err
    end
    if wallet_address ~= address then
        return false, "Wallet address mismatch"
    end
    return true
end

local function verify_bitcoin_cwt(public_key_pem, message, signature, address, alg, chain)
    local pk, err = openssl_pkey.new(public_key_pem, {format = "PEM"})
    if not pk then
        return false, "Failed to load public key: ".. err
    end
    local public_key
    if alg == "secp256k1" then
        local digest, err = openssl_digest.new("sha256")
        if not digest then
            return false, "Failed to new digest.sha256: " .. err
        end
        local ok, err = digest:update(message)
        if not ok then
            return false, "Failed to update digest: " .. err
        end
        local ok, err = pk:verify(signature, digest)
        if not ok then
            return false, "Failed to verify signature: " .. err
        end
        local parameters, err = pk:get_parameters()
        if not parameters then
            return false, "Failed to get parameters: " .. err
        end
        public_key = get_public_key_from_xy(parameters.x, parameters.y)
        if not public_key then
            return false, "Failed to get the public key"
        end
    else
        return false, "Unsupported algorithm: " .. alg
    end
    local wallet_address, err = derive_address_from_pubkey(public_key, chain)
    if not wallet_address then
        return false, "Failed to derive wallet address: " .. err
    end
    if wallet_address ~= address then
        return false, "Wallet address mismatch"
    end
    return true
end

local function check_expiration(token_time, expiration)
    if not token_time then
        return false
    end
    local now = ngx_time()
    if now > token_time + expiration or now < token_time - expiration then
        return false
    end
    return true
end

local function verify_cwt_obj(wallet, cwt_obj, exp)
    if not cwt_obj.valid then
        return cwt_obj
    end

    local chain = cwt_obj[str_const.header][str_const.chain]
    if chain == nil then
        cwt_obj[str_const.reason] = "No chain supplied"
        return cwt_obj
    end
    local public_key_pem = cwt_obj[str_const.header].x5c[1]
    if not public_key_pem then
        cwt_obj[str_const.reason] = "No public key supplied"
        return cwt_obj
    end
    local token_time = cwt_obj[str_const.payload][str_const.time]
    if token_time == nil then
        cwt_obj[str_const.reason] = "No time supplied"
        return cwt_obj
    end
    local exp_ok = check_expiration(token_time, exp)
    if not exp_ok then
        cwt_obj[str_const.reason] = "Token has expired"
        return cwt_obj
    end

    local raw_header = cwt_obj[str_const.raw_underline .. str_const.header]
    local raw_payload = cwt_obj[str_const.raw_underline .. str_const.payload]

    local message = string.format(str_const.cwt_join_msg, raw_header, raw_payload)
    local sig = cwt_decode(cwt_obj[str_const.signature], false)

    if not sig then
        cwt_obj[str_const.reason] = "Wrongly encoded signature"
        return cwt_obj
    end

    local alg = cwt_obj[str_const.header][str_const.alg] or "secp256k1"
    if chain == str_const.chain_ethereum then
        local ok, err = verify_ethereum_cwt(public_key_pem, message, sig, wallet, alg)
        if not ok then
            cwt_obj[str_const.reason] = err
            return cwt_obj
        end
    elseif chain == str_const.chain_ripple or chain == str_const.chain_jingtum then
        local ok, err = verify_ripple_cwt(public_key_pem, message, sig, wallet, alg, chain)
        if not ok then
            cwt_obj[str_const.reason] = err
            return cwt_obj
        end
    elseif chain == str_const.chain_bitcoin then
        local ok, err = verify_bitcoin_cwt(public_key_pem, message, sig, wallet, alg, chain)
        if not ok then
            cwt_obj[str_const.reason] = err
            return cwt_obj
        end
    else
        cwt_obj[str_const.reason] = "Unsupported chain: " .. chain
    end

    if not cwt_obj[str_const.reason] then
        cwt_obj[str_const.verified] = true
        cwt_obj[str_const.reason] = str_const.verified_ok
    end
    return cwt_obj
end

function _M.rewrite(conf, ctx)
    local cwt_token, err = fetch_cwt_token(conf, ctx)
    if not cwt_token then
        core.log.error("failed to fetch cwt token: ", err)
        return 401, {message = "Missing cwt token in request"}
    end

    local cwt_obj = load_cwt(cwt_token)
    if not cwt_obj.valid then
        core.log.error("cwt token invalid: ", cwt_obj.reason)
        return 401, {message = "cwt token invalid"}
    end

    local usr = cwt_obj.payload and cwt_obj.payload.usr
    if not usr then
        return 401, {message = "Missing user in cwt token"}
    end
    local token_time = cwt_obj.payload.time
    if not token_time then
        return 401, {message = "Missing time in cwt token"}
    end

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "usr")

    local consumer = consumers[usr]
    if not consumer then
        return 401, {message = "invalid user in cwt token"}
    end
    local wallet = consumer.auth_conf.wallet

    cwt_obj = verify_cwt_obj(wallet, cwt_obj, consumer.auth_conf.exp)

    if not cwt_obj.verified then
        core.log.error("failed to verify cwt: ", cwt_obj.reason)
        return 401, {message = "Failed to verify cwt"}
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("cwt rewrite ok")
end

return _M