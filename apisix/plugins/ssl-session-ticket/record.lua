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

--- The record of the ssl-session-ticket plugin and the local policy.
--
-- The record is the plugin metadata `/apisix/plugin_metadata/ssl-session-ticket`:
--
--     {
--         "keys": ["<key>", ...],
--         "origin": {
--             "source": "external",
--             "disabled": false,
--             "generated_at": 1793072518,
--             "policy": "3f2a9c1e"
--         }
--     }
--
-- Each key is the base64 of 80 random bytes, encrypted with the
-- `apisix.data_encryption` keyring when `enable_encrypt_fields` is on. The
-- first key issues tickets, all of them decrypt. `origin` is only written by
-- APISIX itself (the Admin API and the built-in generator); a record of a
-- standalone configuration may leave it out.
--
-- Errors never include key material, nor anything derived from it.

local core            = require("apisix.core")
local plugin          = require("apisix.plugin")
local state           = require("apisix.session_ticket.state")
local schema          = require("apisix.plugins.ssl-session-ticket.schema")
local data_encryption = require("apisix.core.data_encryption")
local str_util        = require("resty.string")
local ngx             = ngx
local type            = type
local ipairs          = ipairs
local pairs           = pairs
local tostring        = tostring
local setmetatable    = setmetatable
local str_sub         = string.sub
local encode_base64   = ngx.encode_base64
local decode_base64   = ngx.decode_base64


local NAME = "ssl-session-ticket"
local KEY_SIZE = state.KEY_SIZE
local KEY_NAME_SIZE = state.KEY_NAME_SIZE
local MAX_KEYS = state.MAX_KEYS
local REDACTED = "<redacted>"

local _M = {
    name = NAME,
    etcd_key = "/plugin_metadata/" .. NAME,
}


-- the body of PUT /apisix/admin/plugin_metadata/ssl-session-ticket
_M.metadata_schema = schema.metadata
-- plugin_attr.ssl-session-ticket, the local policy of the nodes executing it
_M.attr_schema = schema.attr


local origin_schema = {
    type = "object",
    properties = {
        source = {type = "string", enum = {"generated", "external"}},
        disabled = {type = "boolean"},
        generated_at = {type = "integer", minimum = 0},
        policy = {type = "string", maxLength = 64},
    },
    required = {"source", "disabled"},
}


--- The local policy, with the defaults filled in.
--
-- @treturn table|nil `{enabled = bool, key_source = "generated"|"external",
-- generated = {rotation_interval = n, max_keys = n}}`
-- @treturn string|nil the error
function _M.policy()
    local attr = plugin.plugin_attr(NAME)
    local conf = type(attr) == "table" and core.table.deepcopy(attr) or {}
    local ok, err = core.schema.check(_M.attr_schema, conf)
    if not ok then
        return nil, "invalid plugin_attr." .. NAME .. ": " .. err
    end

    return conf
end


--- Fingerprint of a local policy: the same on every node configured alike.
function _M.policy_fingerprint(policy)
    local gen = policy.generated or {}
    local s = "enabled=" .. tostring(policy.enabled)
              .. ";key_source=" .. policy.key_source
              .. ";rotation_interval=" .. tostring(gen.rotation_interval)
              .. ";max_keys=" .. tostring(gen.max_keys)
    return str_sub(str_util.to_hex(ngx.sha1_bin(s)), 1, 8)
end


--- Whether the keys are stored encrypted, the same switch as encrypt_fields.
function _M.encryption_enabled()
    return plugin.enable_gde() and true or false
end


local keyring
local function get_keyring()
    if not keyring then
        local local_conf = core.config.local_conf()
        keyring = data_encryption.init_iv_tbl(core.table.try_read_attr(local_conf, "apisix",
                                              "data_encryption", "keyring"))
    end

    return keyring
end


local function encrypt(value)
    local ring = get_keyring()
    if #ring == 0 then
        return nil, "no data_encryption keyring"
    end

    return data_encryption.aes_cbc_encrypt(ring, value)
end


-- like data_encryption.aes_cbc_decrypt, but keeps trying the next key of the
-- keyring when a wrong one happens to produce a valid padding
local function decrypt_key(value)
    for _, cipher in ipairs(get_keyring()) do
        local plain = data_encryption.aes_cbc_decrypt({cipher}, value)
        if plain then
            local raw = decode_base64(plain)
            if raw and #raw == KEY_SIZE then
                return raw
            end
        end
    end

    return nil
end


local function key_error(i, msg)
    return "keys[" .. i .. "] " .. msg
end


-- validate a list of keys and return the raw 80-byte keys; `encrypted` tells
-- whether each item is encrypted with the keyring
local function decode_keys(list, encrypted)
    if type(list) ~= "table" or not core.table.isarray(list) then
        return nil, "keys must be an array"
    end

    if #list > MAX_KEYS then
        return nil, "too many keys, at most " .. MAX_KEYS .. " are allowed"
    end

    local raws = core.table.new(#list, 0)
    local seen = {}
    local names = {}
    for i, item in ipairs(list) do
        if type(item) ~= "string" then
            return nil, key_error(i, "must be a string")
        end

        local raw
        if encrypted then
            raw = decrypt_key(item)
            if not raw then
                return nil, key_error(i, "can not be decrypted with the data_encryption keyring")
            end

        else
            raw = decode_base64(item)
            if not raw then
                return nil, key_error(i, "is not valid base64")
            end

            if #raw ~= KEY_SIZE then
                return nil, key_error(i, "must be the base64 of " .. KEY_SIZE .. " bytes")
            end
        end

        if seen[raw] then
            return nil, key_error(i, "duplicates keys[" .. seen[raw] .. "]")
        end

        local name = str_sub(raw, 1, KEY_NAME_SIZE)
        if names[name] then
            return nil, key_error(i, "has the same key name (first " .. KEY_NAME_SIZE
                                     .. " bytes) as keys[" .. names[name] .. "]")
        end

        seen[raw] = i
        names[name] = i
        raws[i] = raw
    end

    return raws
end


--- Validate the body of an Admin API PUT.
--
-- @treturn table|nil the raw 80-byte keys, in order
-- @treturn string|nil the error
function _M.check_request(body)
    if type(body) ~= "table" then
        return nil, "the body must be an object"
    end

    local ok, err = core.schema.check(_M.metadata_schema, body)
    if not ok then
        return nil, err
    end

    return decode_keys(body.keys, false)
end


local function check_origin(origin, standalone)
    if origin == nil then
        if standalone then
            return true
        end

        return nil, "missing origin"
    end

    if type(origin) ~= "table" then
        return nil, "invalid origin"
    end

    local ok, err = core.schema.check(origin_schema, core.table.deepcopy(origin))
    if not ok then
        return nil, "invalid origin: " .. err
    end

    if standalone and origin.source ~= "external" then
        return nil, "standalone mode only supports external keys"
    end

    return true
end


--- Parse a stored record.
--
-- `opts.standalone` accepts a record without `origin`, whose keys are never
-- encrypted; otherwise the keys are encrypted whenever encrypt_fields is on.
--
-- @treturn table|nil `{keys = {raw...}, source = s, disabled = b, origin = t}`
-- @treturn string|nil the error
function _M.parse(value, opts)
    local standalone = opts and opts.standalone
    if type(value) ~= "table" then
        return nil, "invalid record"
    end

    local ok, err = check_origin(value.origin, standalone)
    if not ok then
        return nil, err
    end

    local keys
    keys, err = decode_keys(value.keys, not standalone and _M.encryption_enabled())
    if not keys then
        return nil, err
    end

    local origin = value.origin
    return {
        keys = keys,
        source = origin and origin.source or "external",
        disabled = origin and origin.disabled or false,
        origin = origin,
    }
end


--- Validate a complete record given in a configuration (standalone).
function _M.check_standalone(value)
    if type(value) ~= "table" then
        return nil, "invalid record"
    end

    for k in pairs(value) do
        if k ~= "id" and k ~= "keys" and k ~= "origin" and k ~= "modifiedIndex" then
            return nil, "unknown field " .. tostring(k)
        end
    end

    return _M.parse(value, {standalone = true})
end


--- Build the record to store.
--
-- @tparam table keys the raw 80-byte keys, in order
-- @tparam table origin the origin envelope
-- @treturn table|nil the record, keys encrypted if needed
-- @treturn string|nil the error
function _M.build(keys, origin)
    local encrypted = _M.encryption_enabled()
    local list = core.table.new(#keys, 0)
    for i, raw in ipairs(keys) do
        local value = encode_base64(raw)
        if encrypted then
            local err
            value, err = encrypt(value)
            if not value then
                -- never fall back to storing the key in clear text
                return nil, "failed to encrypt the keys: " .. (err or "unknown error")
            end
        end

        list[i] = value
    end

    return {
        id = NAME,
        keys = setmetatable(list, core.json.array_mt),
        origin = origin,
    }
end


--- Whether two lists of raw keys are the same, in the same order.
function _M.same_keys(a, b)
    if #a ~= #b then
        return false
    end

    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end

    return true
end


--- A copy of a record without any key material, for responses and dumps.
function _M.redact(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = core.table.deepcopy(value)
    if type(copy.keys) == "table" then
        local keys = core.table.new(#copy.keys, 0)
        for i = 1, #copy.keys do
            keys[i] = REDACTED
        end
        copy.keys = setmetatable(keys, core.json.array_mt)

    elseif copy.keys ~= nil then
        copy.keys = REDACTED
    end

    return copy
end


return _M
