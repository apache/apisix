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

local require        = require
local hmac           = require("resty.hmac")
local resty_sha256   = require("resty.sha256")
local hex_encode     = require("resty.string").to_hex
local pairs          = pairs
local tab_concat     = table.concat
local tab_sort       = table.sort
local tab_insert     = table.insert
local ngx            = ngx
local ngx_escape_uri = ngx.escape_uri
local ngx_re_match   = ngx.re.match
local ngx_re_gmatch  = ngx.re.gmatch
local str_strip      = require("pl.stringx").strip

local ALGO           = "AWS4-HMAC-SHA256"

local _M             = {}


--- hmac256_bin
---
--- @param key string
--- @param msg string
--- @return string hash_binary
function _M.hmac256_bin(key, msg)
    return hmac:new(key, hmac.ALGOS.SHA256):final(msg)
end

--- sha256
---
--- @param msg string
--- @return string hex lowercase hex string
function _M.sha256(msg)
    local hash = resty_sha256:new()
    assert(hash)
    hash:update(msg)
    local digest = hash:final()
    return hex_encode(digest)
end

--- iso8601_to_timestamp
---
--- yyyyMMddTHHmmssZ
---
--- e.g. 20160801T223241Z
--- @param iso8601 string
--- @return integer timestamp utc
function _M.iso8601_to_timestamp(iso8601)
    -- Extract date and time components from the ISO 8601 string
    local match, err = ngx_re_match(iso8601, [[(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z]], "oj")
    if err then
        error(err)
    end

    -- Create a table compatible with os.time
    local datetime = {
        year = tonumber(match[1]),
        month = tonumber(match[2]),
        day = tonumber(match[3]),
        hour = tonumber(match[4]),
        min = tonumber(match[5]),
        sec = tonumber(match[6])
    }

    -- Convert to Unix timestamp
    local offset = os.time() - os.time(os.date("!*t"))
    local timestamp = os.time(datetime) + offset

    return timestamp
end

--- aws_uri_encode
---
--- Encode a string for use in the path of a URL; uses URLEncoder.encode,
--- (which encodes a string for use in the query portion of a URL), then
--- applies some postfilters to fix things up per the RFC. Can optionally
--- handle strings which are meant to encode a path (ie include '/'es
--- which should NOT be escaped).
--- @param value string the value to encode
--- @param path boolean true if the value is intended to represent a path
--- @return string encoded the encoded value
function _M.aws_uri_encode(value, path)
    if (not value) or #value == 0 then
        return ""
    end

    local encoded = ngx_escape_uri(value)

    -- match
    -- !
    -- *
    -- (
    -- )
    -- '
    -- %2F                 / when path encode
    --
    -- other to pass
    -- (%[A-Z0-9]{2})      uri encoded
    -- [A-Za-z0-9\-\._\~]  reserved characters

    local iterator, err = ngx_re_gmatch(encoded,
        "!|\\*|\\(|\\)|'|%2F|(%[A-Z0-9]{2})|[A-Za-z0-9\\-\\._\\~]"
        , "oj")
    if not iterator then
        error(err)
    end

    local replacement = {}

    while true do
        local m, err = iterator()
        if err then
            error(err)
        end

        if not m then
            -- no match found (any more)
            break
        end

        -- found a match
        if m[0] == "!" then
            tab_insert(replacement, "%21")
        elseif m[0] == "*" then
            tab_insert(replacement, "%2A")
        elseif m[0] == "(" then
            tab_insert(replacement, "%28")
        elseif m[0] == ")" then
            tab_insert(replacement, "%29")
        elseif m[0] == "'" then
            tab_insert(replacement, "%27")
        elseif path and m[0] == "%2F" then
            tab_insert(replacement, "/")
        else
            tab_insert(replacement, m[0])
        end
    end

    return tab_concat(replacement)
end

--- build_canonical_uri
---
--- e.g. input "foo///bar" output "/foo/bar"
--- @param uri string
--- @return string canonical_uri
function _M.build_canonical_uri(uri)
    if uri == "" then
        return "/"
    end

    if uri ~= "/" then
        -- rm suffix slash
        if uri:sub(-1, -1) == "/" then
            uri = uri:sub(1, -2)
        end
        -- add prefix slash
        if uri:sub(1, 1) ~= "/" then
            uri = "/" .. uri
        end
    end

    return _M.aws_uri_encode(uri, true)
end

--- build_canonical_query_string
---
--- @param query_string table<string, string>
--- @return string canonical_query_string
function _M.build_canonical_query_string(query_string)
    local canonical_qs_table = {}
    local canonical_qs_i = 0
    for k, v in pairs(query_string) do
        canonical_qs_i = canonical_qs_i + 1
        canonical_qs_table[canonical_qs_i] = _M.aws_uri_encode(k, false)
            .. "=" .. _M.aws_uri_encode(v, false)
    end

    tab_sort(canonical_qs_table)
    local canonical_qs = tab_concat(canonical_qs_table, "&")

    return canonical_qs
end

--- build_canonical_headers
---
--- @param headers table<string, string>
--- @return string canonical_headers, string signed_headers
function _M.build_canonical_headers(headers)
    local canonical_headers_table, signed_headers_list = {}, {}
    local signed_headers_i = 0
    for k, v in pairs(headers) do
        k = k:lower()

        signed_headers_i = signed_headers_i + 1
        signed_headers_list[signed_headers_i] = k
        -- strip starting and trailing spaces including strip multiple spaces into single space
        canonical_headers_table[k] = str_strip(v)
    end
    tab_sort(signed_headers_list)

    for i = 1, #signed_headers_list do
        local k = signed_headers_list[i]
        canonical_headers_table[i] = k .. ":" .. canonical_headers_table[k] .. "\n"
    end

    local canonical_headers = tab_concat(canonical_headers_table, nil)
    local signed_headers = tab_concat(signed_headers_list, ";")

    return canonical_headers, signed_headers
end

--- create_signing_key
--- @param secret_key string
--- @param datestamp string
--- @param region string
--- @param service string
--- @return string binary
function _M.create_signing_key(secret_key, datestamp, region, service)
    local date_key                = _M.hmac256_bin("AWS4" .. secret_key, datestamp)
    local date_region_key         = _M.hmac256_bin(date_key, region)
    local date_region_service_key = _M.hmac256_bin(date_region_key, service)
    local signing_key             = _M.hmac256_bin(date_region_service_key, "aws4_request")
    return signing_key
end

--- generate_signature
---
--- @param method string
--- @param uri string
--- @param query_string table<string, string>? Should not include Signature like 'X-Amz-Signature'
--- @param headers table<string, string>? Should not include Signature like 'X-Amz-Signature'
--- @param body string?
--- @param secret_key string
--- @param time integer UTC seconds timestamp
--- @param region string
--- @param service string
--- @return string signature
function _M.generate_signature(method, uri, query_string,
                               headers, body, secret_key, time, region, service)
    -- Step 1: Create a canonical request

    -- computing canonical uri
    local canonical_uri = _M.build_canonical_uri(uri)

    -- computing canonical query string
    local canonical_qs = ""
    if query_string then
        canonical_qs = _M.build_canonical_query_string(query_string)
    end

    -- computing canonical headers
    local canonical_headers, signed_headers = "", ""
    if headers then
        canonical_headers, signed_headers = _M.build_canonical_headers(headers)
    end

    -- default no body hash
    local body_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    if body and body ~= "" then
        body_hash = _M.sha256(body)
    end

    local canonical_request = method:upper() .. "\n"
        .. canonical_uri .. "\n"
        .. (canonical_qs or "") .. "\n"
        .. canonical_headers .. "\n"
        .. signed_headers .. "\n"
        .. body_hash

    -- Step 2: Create a hash of the canonical request
    local hashed_canonical_request = _M.sha256(canonical_request)


    -- Step 3: Create a string to sign
    local amzdate   = os.date("!%Y%m%dT%H%M%SZ", time) -- ISO 8601 20130524T000000Z
    local datestamp = os.date("!%Y%m%d", time)         -- Date w/o time, used in credential scope


    local credential_scope = datestamp .. "/" .. region .. "/" .. service .. "/aws4_request"
    local string_to_sign   = ALGO .. "\n"
        .. amzdate .. "\n"
        .. credential_scope .. "\n"
        .. hashed_canonical_request


    -- Step 4: Calculate the signature
    ---@cast datestamp string
    local signing_key = _M.create_signing_key(secret_key, datestamp, region, service)
    local signature   = hex_encode(_M.hmac256_bin(signing_key, string_to_sign))

    return signature
end

return _M
