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

--- AWS SigV4 signing helper for AI providers.
-- Signs outgoing HTTP requests using AWS Signature Version 4.

require("resty.aws.config")  -- reads env vars before init
local aws = require("resty.aws")
local core = require("apisix.core")
local signer = require("resty.aws.request.sign")
local ngx = ngx
local ngx_escape_uri = ngx.escape_uri

local aws_instance


-- Decode each path segment then re-encode N times. Idempotent: handles both
-- raw paths (e.g. "/model/foo:bar/x") and once-encoded paths (e.g.
-- "/model/foo%3Abar/x") uniformly.
--   N=1 → once-encoded path (for HTTP wire transport)
--   N=2 → twice-encoded path (for AWS SigV4 canonical URI)
local function normalize_and_encode_path(path, n)
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        local s = ngx.unescape_uri(segment)
        for _ = 1, n do
            s = ngx_escape_uri(s)
        end
        segments[#segments + 1] = s
    end
    return "/" .. table.concat(segments, "/")
end

local _M = {}


--- Sign an outgoing HTTP request with AWS SigV4.
-- Must be called AFTER params.body is finalized (SigV4 signs body hash).
-- After signing, params.body is a JSON string (not a table).
--
-- params.path may be either a raw path or once-encoded; this function
-- normalizes both to the same encoded form for HTTP transport and computes
-- the double-encoded canonical URI for SigV4.
--
-- @param params table  HTTP request params {method, host, port, path, headers, body, query}
-- @param aws_conf table  {access_key_id, secret_access_key, session_token}
-- @param region string  AWS region for SigV4 credential scope
-- @return nil on success, or error string on failure
function _M.sign_request(params, aws_conf, region)
    -- Validate path: required for canonical URI construction
    if type(params.path) ~= "string" or params.path == "" then
        return "missing or invalid path for SigV4 signing"
    end

    -- Normalize the input path to once-encoded form for HTTP wire transport.
    -- This is idempotent across raw and once-encoded inputs.
    params.path = normalize_and_encode_path(params.path, 1)

    -- Serialize body to JSON string (SigV4 signs the exact bytes)
    if type(params.body) == "table" then
        local body_str, err = core.json.encode(params.body)
        if not body_str then
            return "failed to encode body: " .. (err or "")
        end
        params.body = body_str
    end

    -- Create AWS instance (singleton)
    if not aws_instance then
        aws_instance = aws()
    end

    -- Create Credentials object with :get() method as required by resty.aws signer
    local credentials = aws_instance:Credentials({
        accessKeyId = aws_conf.access_key_id,
        secretAccessKey = aws_conf.secret_access_key,
        sessionToken = aws_conf.session_token,
    })

    -- Build the config object expected by resty.aws.request.sign
    local config = {
        region = region,
        signatureVersion = "v4",
        endpointPrefix = "bedrock",
        credentials = credentials,
    }

    -- Build the request object to sign.
    -- params.path is already once-encoded for the HTTP wire (e.g., %3A for :).
    -- For the SigV4 canonical URI, AWS requires reserved characters to be
    -- encoded twice (e.g., raw ":" → "%3A" on the wire → "%253A" in the
    -- canonical URI). normalize_and_encode_path with n=2 decodes each segment
    -- then re-encodes it twice, producing the required double-encoded form.
    local r = {
        headers = {},
        method = params.method or "POST",
        canonicalURI = normalize_and_encode_path(params.path, 2),
        host = params.host,
        port = params.port or 443,
        body = params.body,
        query = params.query,
    }

    local signed, err = signer(config, r)
    if not signed then
        return "SigV4 signing failed: " .. (err or "unknown")
    end

    -- Copy signed auth headers back to params using lowercase keys to match the
    -- convention used by construct_forward_headers() in http.lua and avoid
    -- duplicate headers (e.g. both "Authorization" and "authorization").
    if signed.headers then
        if signed.headers["Authorization"] then
            params.headers["authorization"] = signed.headers["Authorization"]
        end
        if signed.headers["X-Amz-Date"] then
            params.headers["x-amz-date"] = signed.headers["X-Amz-Date"]
        end
        if signed.headers["X-Amz-Security-Token"] then
            params.headers["x-amz-security-token"] = signed.headers["X-Amz-Security-Token"]
        end
        if signed.headers["Host"] then
            params.headers["host"] = signed.headers["Host"]
        end
    end

    return nil
end


return _M
