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

local core         = require("apisix.core")
local resty_sha256 = require("resty.sha256")
local str          = require("resty.string")
local math         = math

local _M = {}

local U32_MAX = 4294967295

-- Collapse a float to an integer in milli-units.
-- Negative and NaN map to 0; infinity and overflow saturate to U32_MAX.
local function quantise_milli(v)
    if type(v) ~= "number" then
        return nil
    end
    if v ~= v then
        -- NaN
        return 0
    end
    if v < 0 then
        return 0
    end
    local s = v * 1000
    if s == math.huge or s > U32_MAX then
        return U32_MAX
    end
    return math.floor(s)
end

-- Build the output-affecting fingerprint table from the effective request body
-- and optional opts = { protocol, instance }.
local function fingerprint(req, opts)
    return {
        model            = req.model,
        messages         = req.messages,
        temperature      = quantise_milli(req.temperature),
        top_p            = quantise_milli(req.top_p),
        presence_penalty = quantise_milli(req.presence_penalty),
        frequency_penalty = quantise_milli(req.frequency_penalty),
        max_tokens       = req.max_tokens,
        seed             = req.seed,
        n                = req.n,
        top_logprobs     = req.top_logprobs,
        logprobs         = req.logprobs,
        logit_bias       = req.logit_bias,
        tools            = req.tools,
        tool_choice      = req.tool_choice,
        parallel_tool_calls = req.parallel_tool_calls,
        response_format  = req.response_format,
        stop             = req.stop,
        stream           = req.stream and true or false,
        protocol         = opts and opts.protocol or nil,
        instance         = opts and opts.instance or nil,
    }
end

-- _M.build(req, opts) -> "ai-cache:l1::<sha256hex>"
--   req  : effective request body table
--   opts : optional { protocol = <string>, instance = <string> }
function _M.build(req, opts)
    local fp = fingerprint(req, opts)
    local canonical = core.json.stably_encode(fp)
    local sha = resty_sha256:new()
    sha:update(canonical)
    local hex = str.to_hex(sha:final())
    -- "ai-cache:l1:<scope>:<request>" — scope is empty in Phase 1a/1b;
    -- Phase 1d fills the middle segment with a consumer/vars hash.
    return "ai-cache:l1::" .. hex
end

return _M
