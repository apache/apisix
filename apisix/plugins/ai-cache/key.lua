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

local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")
local rapidjson = require("rapidjson")
local sha256    = require("resty.sha256")
local to_hex    = require("resty.string").to_hex

local ipairs       = ipairs
local pairs        = pairs
local type         = type
local getmetatable = getmetatable
local concat       = table.concat

local rapidjson_null = rapidjson.null
local ENCODE_OPTS    = { sort_keys = true }

local _M = {}


local function hex_digest(s)
    local hash = sha256:new()
    hash:update(s)
    return to_hex(hash:final())
end


local function to_rapidjson_value(data)
    if data == core.json.null then
        return rapidjson_null
    end
    if type(data) ~= "table" then
        return data
    end
    if getmetatable(data) == core.json.array_mt then
        local arr = {}
        for i, v in ipairs(data) do
            arr[i] = to_rapidjson_value(v)
        end
        return rapidjson.array(arr)
    end
    local obj = {}
    for k, v in pairs(data) do
        obj[k] = to_rapidjson_value(v)
    end
    return obj
end


local function canonical_encode(value)
    return rapidjson.encode(to_rapidjson_value(value), ENCODE_OPTS)
end


function _M.fingerprint(ctx, body)
    local params = core.table.deepcopy(body)
    params.messages = nil
    params.model    = nil
    params.stream   = nil

    local repr = canonical_encode({
        protocol = ctx.ai_client_protocol or "",
        model    = ctx.var.request_llm_model or body.model or "",
        messages = protocols.get_messages(body, ctx) or {},
        params   = params,
    })
    return hex_digest(repr)
end


function _M.scope(conf, ctx)
    local ck = conf.cache_key
    local inc_vars = ck and ck.include_vars
    if not (ck and ck.include_consumer) and (not inc_vars or #inc_vars == 0) then
        return "shared"
    end

    local parts = {}
    if ck.include_consumer then
        parts[#parts + 1] = "consumer=" .. (ctx.consumer_name or "")
    end
    if inc_vars then
        for _, name in ipairs(inc_vars) do
            parts[#parts + 1] = name .. "=" .. (ctx.var[name] or "")
        end
    end
    return concat(parts, ":")
end


return _M
