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

local _M = {}

-- Phase 1a fingerprint: {model, messages}. Phase 1b expands the whitelist;
-- Phase 1c swaps the input from the client body to the effective body.
local function fingerprint(body)
    return {
        model    = body.model,
        messages = body.messages,
    }
end

function _M.build(body)
    local fp = fingerprint(body)
    local canonical = core.json.stably_encode(fp)
    local sha = resty_sha256:new()
    sha:update(canonical)
    local hex = str.to_hex(sha:final())
    -- "ai-cache:l1:<scope>:<request>" — scope is empty in Phase 1a;
    -- Phase 1d fills the middle segment with a consumer/vars hash.
    return "ai-cache:l1::" .. hex
end

return _M
