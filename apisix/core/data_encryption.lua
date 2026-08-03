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

--- Generic AES-CBC data encryption used by the `data_encryption.keyring`
-- (plugin `encrypt_fields`). The primitives are keyring-agnostic so other
-- callers (e.g. SSL key encryption) can reuse them with their own keyring.
--
-- @module core.data_encryption

local log               = require("apisix.core.log")
local tbl               = require("apisix.core.table")
local fetch_local_conf  = require("apisix.core.config_local").local_conf
local aes               = require("resty.aes")
local ffi               = require("ffi")

local C                 = ffi.C
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local type              = type
local ipairs            = ipairs
local assert            = assert

ffi.cdef[[
unsigned long ERR_peek_error(void);
void ERR_clear_error(void);
]]


local _M = {}


--- Build a table of AES-128-CBC ciphers from a keyring, each using the key
-- itself as the IV.
function _M.init_iv_tbl(ivs)
    local iv_tbl = tbl.new(2, 0)
    if type(ivs) == "string" then
        ivs = {ivs}
    end

    if type(ivs) == "table" then
        for _, iv in ipairs(ivs) do
            tbl.insert(iv_tbl, assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv = iv})))
        end
    end

    return iv_tbl
end


--- Encrypt `value` with the first cipher of `iv_tbl` and base64-encode it.
function _M.aes_cbc_encrypt(iv_tbl, value)
    local aes_cbc_with_iv = iv_tbl[1]
    if aes_cbc_with_iv == nil then
        return nil, "no keyring configured"
    end

    local encrypted = aes_cbc_with_iv:encrypt(value)
    if encrypted == nil then
        return nil, "failed to encrypt"
    end

    return ngx_encode_base64(encrypted)
end


--- Base64-decode `value`, then try to decrypt it with each cipher of `iv_tbl`.
-- `subject` (optional) is a noun describing what is being decrypted; it is woven
-- into the error message so callers get a meaningful reason (e.g. "ssl key" ->
-- "base64 decode ssl key failed"). Generic messages are used when omitted.
function _M.aes_cbc_decrypt(iv_tbl, value, subject)
    local what = subject and (subject .. " ") or ""

    local decoded = ngx_decode_base64(value)
    if not decoded then
        return nil, "base64 decode " .. what .. "failed"
    end

    for _, aes_cbc_with_iv in ipairs(iv_tbl) do
        local decrypted = aes_cbc_with_iv:decrypt(decoded)
        if decrypted then
            return decrypted
        end

        if C.ERR_peek_error() then
            -- clean up the error queue of OpenSSL to prevent
            -- normal requests from being interfered with.
            C.ERR_clear_error()
        end
    end

    return nil, "decrypt " .. what .. "failed"
end


local _keyring
local function get_keyring()
    if _keyring == nil then
        local local_conf = fetch_local_conf()
        local ivs = tbl.try_read_attr(local_conf, "apisix", "data_encryption", "keyring")
        _keyring = _M.init_iv_tbl(ivs)
    end

    return _keyring
end


--- Encrypt a plugin `encrypt_fields` value with the `data_encryption.keyring`.
-- Returns `value` unchanged when no keyring is configured.
function _M.encrypt(value)
    local keyring = get_keyring()
    if #keyring == 0 then
        return value
    end

    local encrypted, err = _M.aes_cbc_encrypt(keyring, value)
    if not encrypted then
        log.error("failed to encrypt the data: ", err)
        return value
    end

    return encrypted
end


--- Decrypt a plugin `encrypt_fields` value with the `data_encryption.keyring`.
-- Returns `value` unchanged when no keyring is configured. `subject` (optional)
-- is forwarded to qualify the error message.
function _M.decrypt(value, subject)
    local keyring = get_keyring()
    if #keyring == 0 then
        return value
    end

    return _M.aes_cbc_decrypt(keyring, value, subject)
end


return _M
