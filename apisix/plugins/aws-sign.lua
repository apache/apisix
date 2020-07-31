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
local hmac = require "resty.hmac"
local sha256 = require('resty.sha256')

local plugin_name = "aws_sign"
local string = string
local now = ngx.now
local os = os
local ngx_req = ngx.req
local ngx_var = ngx.var
local type = type
local resty_string = require "resty.string"
local escape_uri = ngx.escape_uri
local tsort = table.sort
local tconcat = table.concat
local tonumber = tonumber


local schema = {
    type = "object",
    properties = {
        access_key = {type = "string", minLength = 10,maxLength = 32,pattern = [[^[a-zA-Z0-9_-]{5,32}$]]},
        secret_key = {type = "string", minLength = 10,maxLength = 32,pattern = [[^[a-zA-Z0-9_-]{5,32}$]]},
        signed_headers = {
            type = "array",
            items = {type = "string"},
        },
        region = {type = "string", minLength = 0, default = ""},
        version = {type = "string", minLength = 0, default = "apisix"},
        service_name = {type = "string", minLength = 0, default = ""},
        expire_time = {type = "integer", minimum = 0, default = 600},
    },
    required = {"access_key", "secret_key"}
}

local _M = {
    version = 0.1,
    priority = 2513,
    type = 'aws_sign',
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    conf.signed_headers = conf.signed_headers or {}

    local signed_headers_size = 1
    for k, v in ipairs(conf.signed_headers) do
        conf.signed_headers[k] = trim(string.lower(v))
        signed_headers_size = signed_headers_size + 1
    end

    conf.signed_headers[signed_headers_size] = 'host'
    signed_headers_size = signed_headers_size + 1
    conf.signed_headers[signed_headers_size] = 'content-type'
    signed_headers_size = signed_headers_size + 1
    conf.signed_headers[signed_headers_size] = 'x-amz-date'

    return true
end

local function trim(str, sep)
    local pattern
    if sep ~= nil then
        pattern = string.format("^%s*([^%s]*)%s*$", sep, sep, sep)
    else
        pattern = [[^\s*(.*?)\s*$]]
    end
    local newstr, n, err = ngx.re.gsub(str, pattern, "$1")
    return newstr
end

local function split(str, sep)
    local sep, fields = sep or "%s", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end


local function sha256_digest(str)
    local h = sha256:new()
    h:update(str or '')
    return resty_string.to_hex(h:final())
end

local function hmac_sha256(key, str, to_hex)
    local h_date = hmac:new(key, hmac.ALGOS.SHA256)
    return h_date:final(str, to_hex)
end

local function get_hashed_canonical_request(ctx, request_method, uri, query_string, signed_headers, requset_body_digest)
    local canonical_request = request_method .. "\n"
            .. uri .. "\n"
            .. query_string .. "\n"

    local signed_headers_str = ""
    for _, header_name in ipairs(signed_headers) do
        local header = core.request.header(ctx, header_name)
        if header_name == "x-amz-content-sha256" then
            header = requset_body_digest
        elseif header == nil  then
            return nil, "missing http header" .. header_name
        end
        
        canonical_request = canonical_request .. string.lower(header_name) .. ":" .. trim(header) .. "\n"
        signed_headers_str = signed_headers_str ..  string.lower(header_name)  .. ";"
    end
    canonical_request = canonical_request .. "\n"
    canonical_request = canonical_request ..  string.sub(signed_headers_str, 1, -2) .. "\n"
    canonical_request = canonical_request .. requset_body_digest

    return sha256_digest(canonical_request)
end

local function get_signature_key(secret_key, date_stamp, region, service_name, sign_version)
    local k_date = hmac_sha256(string.upper(sign_version) .. secret_key, date_stamp)
    local k_region = hmac_sha256(k_date, region)
    local k_service = hmac_sha256(k_region, service_name)
    return hmac_sha256(k_service, string.lower(sign_version) .. '_request')
end


function _M.rewrite(conf, ctx)
    local all_header = core.request.headers(ctx)
    local authorization = all_header["authorization"]

    local amzdate =  core.request.header(ctx,"x-amz-date")

    if not amzdate or string.len(amzdate) < 10  then
        return 400, {message = "header 'x-amz-date' is needed"}
    end
    
    if not authorization or string.len(authorization) < 10 then
        return 400, {message = "invalid authorization"}
    end

    core.log.info("authorization is:", authorization, " conf is: ",core.json.delay_encode(conf))

    local auth_table = split(authorization, " ")

    if type(auth_table) ~= "table" and #auth_table ~= 4 then
        return 400, {message = "invalid authorization"}
    end

    if auth_table[1] == nil or auth_table[1] ~= conf.version .. "-HMAC-SHA256" then
        return 400, {message = "invalid sign method"}
    end

    local credential_str = trim(string.sub(auth_table[2], 12), ",")
    local credential_table = split(credential_str, "/")
    if type(credential_table) ~= "table" and #credential_table ~= 5 then
        return 400, {message = "invalid authorization"}
    end

    local timestamp = now()
    local time_zone = os.difftime(timestamp, os.time(os.date("!*t", timestamp)))

    local time_table = {
        year = tonumber(string.sub(amzdate, 1, -13)) or 0,
        month = tonumber(string.sub(amzdate, -12, -11)) or 0,
        day = tonumber(string.sub(amzdate, -10, -9)) or 0,
        hour = tonumber(string.sub(amzdate, -7, -6)) or 0,
        min = tonumber(string.sub(amzdate, -5, -4)) or 0,
        sec = tonumber(string.sub(amzdate, -3, -2))  or 0
    }

    local date_to_timestamp = os.time(time_table) + time_zone
    local diff_time = os.difftime(timestamp, date_to_timestamp)

    if diff_time > conf.expire_time or diff_time < -3600  then
        return 400, {message = "signature expireed"}
    end

    local access_key = credential_table[1]

    if access_key ~= conf.access_key then
        return 400, {message = "invalid access_key"}
    end


    local signed_headers_str = trim(auth_table[3], ",")
    signed_headers_str = string.sub(signed_headers_str, 15)
    local signed_headers = split(signed_headers_str, ";") or {}
    all_header["host"] =  ngx_var.host

    tsort(signed_headers)

    local credential_scope = credential_table[2] .. "/" .. credential_table[3]
            .. "/" .. credential_table[4] .. "/" .. credential_table[5]


    local request_method = ngx_req.get_method()
    local canonical_uri = ngx_var.uri
    local canonical_query_string = ""
    local args, _ = ngx.req.get_uri_args()


    if type(args) == "table" then
        local keys = {}
        local query_tab = {}
        local query_tab_size = 1

        for k,v in pairs(args) do
            table.insert(keys, k)
        end
        tsort(keys)

        for _, key in pairs(keys) do
            local param = args[key]
            if type(param) == "table" then
                for _, vval in pairs(param) do
                    query_tab[query_tab_size] = escape_uri(key) .. "=" .. escape_uri(vval)
                    query_tab_size = query_tab_size + 1
                end
            else
                query_tab[query_tab_size] = escape_uri(key) .. "=" .. escape_uri(param)
                query_tab_size = query_tab_size + 1
            end
        end
        canonical_query_string = tconcat(query_tab, "&")
    end

    local date_stamp = credential_table[2]
    local region = credential_table[3]
    local service_name = credential_table[4]
    local request_name = credential_table[5]

    if region ~= conf.region then
        return 400, {message = "invalid region"}
    end

    if service_name ~= string.lower(conf.service_name) then
        return 400, {message = "invalid service name"}
    end

    if request_name ~= string.lower(conf.version .. "_request") then
        return 400, {message = "invalid sign  version"}
    end

    local request_body = core.request.get_body() or ""
    local body_digest = sha256_digest(request_body)

    local canonical_request_str, err = get_hashed_canonical_request(ctx, request_method, canonical_uri,
            canonical_query_string, signed_headers, body_digest)

    if not canonical_request_str then
        return 400, {message = err}
    end

    local string_to_sign = conf.version .. "-HMAC-SHA256" .. "\n" .. amzdate .. "\n" .. credential_scope .. "\n"
          .. canonical_request_str

    local signing_key = get_signature_key(conf.secret_key, date_stamp, region, service_name, conf.version)
    local signature = hmac_sha256(signing_key, string_to_sign, true)
    local request_sign = string.sub(auth_table[4], 11)

    if request_sign ~= signature then
        return 400, {message = "invalid signature"}
    end

end

return _M
