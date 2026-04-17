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
local ngx_escape_uri = ngx.escape_uri

local aws_instance


-- Encode a URL path for AWS SigV4 canonical URI.
-- AWS SigV4 requires each path segment to be URI-encoded twice. This function
-- applies a single ngx.escape_uri pass per segment; the second encoding pass
-- comes from the caller's input, which is expected to already be URL-encoded
-- (e.g. bedrock.lua escapes the model ID before building the path, turning
-- raw ":" into "%3A"). Running ngx.escape_uri here then escapes the "%" to
-- "%25", yielding the "%253A" required by the canonical URI.
local function encode_path_for_canonical_uri(path)
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        -- Encodes any unreserved chars and re-escapes "%" from the upstream
        -- encoding pass, producing the double-encoded form SigV4 expects.
        segments[#segments + 1] = ngx_escape_uri(segment)
    end
    return "/" .. table.concat(segments, "/")
end

local _M = {}


--- Sign an outgoing HTTP request with AWS SigV4.
-- Must be called AFTER params.body is finalized (SigV4 signs body hash).
-- After signing, params.body is a JSON string (not a table).
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
    -- The HTTP path may contain URL-encoded chars (e.g., %3A for : in model IDs).
    -- AWS SigV4 requires double-encoding in the canonical URI: %3A → %253A.
    -- We pass canonicalURI with the double-encoded path so the signer uses it as-is.
    local r = {
        headers = {},
        method = params.method or "POST",
        canonicalURI = encode_path_for_canonical_uri(params.path),
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
