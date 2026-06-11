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

local ngx = ngx
local hmac = require("resty.hmac")
local hex_encode = require("resty.string").to_hex
local resty_sha256 = require("resty.sha256")
local str_strip = require("pl.stringx").strip
local norm_path = require("pl.path").normpath
local pairs = pairs
local ipairs = ipairs
local type = type
local str_format = string.format
local str_byte = string.byte
local tab_concat = table.concat
local tab_sort = table.sort
local os = os


local plugin_name = "aws-lambda"
local plugin_version = 0.1
local priority = -1899

local ALGO = "AWS4-HMAC-SHA256"

local function hmac256(key, msg)
    return hmac:new(key, hmac.ALGOS.SHA256):final(msg)
end

local function sha256(msg)
    local hash = resty_sha256:new()
    hash:update(msg)
    local digest = hash:final()
    return hex_encode(digest)
end

-- URI-encode a string per the AWS SigV4 spec: percent-encode every character
-- except the RFC3986 unreserved characters A-Z, a-z, 0-9, "-", "_", "." and "~"
local function uri_encode(s)
    return (s:gsub("[^A-Za-z0-9%-_.~]", function(c)
        return str_format("%%%02X", str_byte(c))
    end))
end

local function get_signature_key(key, datestamp, region, service)
    local kDate = hmac256("AWS4" .. key, datestamp)
    local kRegion = hmac256(kDate, region)
    local kService = hmac256(kRegion, service)
    local kSigning = hmac256(kService, "aws4_request")
    return kSigning
end

local aws_authz_schema = {
    type = "object",
    properties = {
        -- API Key based authorization
        apikey = {type = "string"},
        -- IAM role based authorization, works via aws v4 request signing
        -- more at https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
        iam = {
            type = "object",
            properties = {
                accesskey = {
                    type = "string",
                    description = "access key id from from aws iam console"
                },
                secretkey = {
                    type = "string",
                    description = "secret access key from from aws iam console"
                },
                aws_region = {
                    type = "string",
                    default = "us-east-1",
                    description = "the aws region that is receiving the request"
                },
                service = {
                    type = "string",
                    default = "execute-api",
                    description = "the service that is receiving the request"
                }
            },
            required = {"accesskey", "secretkey"}
        }
    }
}

local function request_processor(conf, ctx, params)
    local headers = params.headers
    -- set authorization headers if not already set by the client
    -- we are following not to overwrite the authz keys
    if not headers["x-api-key"] then
        if conf.authorization and conf.authorization.apikey then
            headers["x-api-key"] = conf.authorization.apikey
            return
        end
    end

    -- performing aws v4 request signing for IAM authorization
    -- visit https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
    -- to look at the pseudocode in python.
    if headers["authorization"] or not conf.authorization or not conf.authorization.iam then
        return
    end

    -- create a date for headers and the credential string
    local t = ngx.time()
    local amzdate =  os.date("!%Y%m%dT%H%M%SZ", t)
    local datestamp = os.date("!%Y%m%d", t) -- Date w/o time, used in credential scope
    headers["X-Amz-Date"] = amzdate

    -- computing canonical uri
    local canonical_uri = norm_path(params.path)
    if canonical_uri ~= "/" then
        if canonical_uri:sub(-1, -1) == "/" then
            canonical_uri = canonical_uri:sub(1, -2)
        end
        if canonical_uri:sub(1, 1) ~= "/" then
            canonical_uri = "/" .. canonical_uri
        end
    end

    -- computing canonical query string: URI-encode the name and value of
    -- every pair, then sort the pairs by encoded name and encoded value.
    -- params.query holds the percent-decoded args: a table value means the
    -- arg appears multiple times and a true value means an arg without value
    local query_pairs = {}
    local query_pairs_i = 0
    for k, v in pairs(params.query) do
        local name = uri_encode(k)
        if type(v) ~= "table" then
            v = {v}
        end
        for _, value in ipairs(v) do
            if value == true then
                value = ""
            end
            query_pairs_i = query_pairs_i + 1
            query_pairs[query_pairs_i] = {name, uri_encode(value)}
        end
    end

    tab_sort(query_pairs, function(a, b)
        if a[1] ~= b[1] then
            return a[1] < b[1]
        end
        return a[2] < b[2]
    end)

    local canonical_qs = {}
    for i = 1, query_pairs_i do
        canonical_qs[i] = query_pairs[i][1] .. "=" .. query_pairs[i][2]
    end
    canonical_qs = tab_concat(canonical_qs, "&")

    -- send exactly the query string that gets signed: lua-resty-http passes
    -- a string through unmodified, while a table would be re-encoded by
    -- ngx.encode_args whose output may differ from the signed string
    params.query = canonical_qs

    -- computing canonical and signed headers

    local canonical_headers, signed_headers = {}, {}
    local signed_headers_i = 0
    for k, v in pairs(headers) do
        k = k:lower()
        if k ~= "connection" then
            signed_headers_i = signed_headers_i + 1
            signed_headers[signed_headers_i] = k
            -- strip starting and trailing spaces including strip multiple spaces into single space
            canonical_headers[k] =  str_strip(v)
        end
    end
    tab_sort(signed_headers)

    for i = 1, #signed_headers do
        local k = signed_headers[i]
        canonical_headers[i] = k .. ":" .. canonical_headers[k] .. "\n"
    end
    canonical_headers = tab_concat(canonical_headers, nil, 1, #signed_headers)
    signed_headers = tab_concat(signed_headers, ";")

    -- combining elements to form the canonical request (step-1)
    local canonical_request = params.method:upper() .. "\n"
                        .. canonical_uri .. "\n"
                        .. (canonical_qs or "") .. "\n"
                        .. canonical_headers .. "\n"
                        .. signed_headers .. "\n"
                        .. sha256(params.body or "")

    -- creating the string to sign for aws signature v4 (step-2)
    local iam = conf.authorization.iam
    local credential_scope = datestamp .. "/" .. iam.aws_region .. "/"
                            .. iam.service .. "/aws4_request"
    local string_to_sign = ALGO .. "\n"
                        .. amzdate .. "\n"
                        .. credential_scope .. "\n"
                        .. sha256(canonical_request)

    -- calculate the signature (step-3)
    local signature_key = get_signature_key(iam.secretkey, datestamp, iam.aws_region, iam.service)
    local signature = hex_encode(hmac256(signature_key, string_to_sign))

    -- add info to the headers (step-4)
    headers["authorization"] = ALGO .. " Credential=" .. iam.accesskey
                            .. "/" .. credential_scope
                            .. ", SignedHeaders=" .. signed_headers
                            .. ", Signature=" .. signature
end


local serverless_obj = require("apisix.plugins.serverless.generic-upstream")

local plugin = serverless_obj(plugin_name, plugin_version, priority, request_processor,
                              aws_authz_schema)

-- encrypt sensitive credential fields at rest
plugin.schema.encrypt_fields = {
    "authorization.apikey",
    "authorization.iam.accesskey",
    "authorization.iam.secretkey",
}

return plugin
