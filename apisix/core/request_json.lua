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

local config_local = require("apisix.core.config_local")
local core_json = require("apisix.core.json")
local qjson = require("qjson")
local simdjson = require("resty.simdjson")
local pcall = pcall
local tostring = tostring


local simdjson_parser, simdjson_err = simdjson.new()
assert(simdjson_parser, simdjson_err)
local configured_name

local _M = {}


local function qjson_decode(str)
    local ok, decoded, err = pcall(qjson.decode, str)
    if not ok then
        return nil, tostring(decoded)
    end

    if decoded == nil then
        return nil, err
    end

    ok, decoded, err = pcall(qjson.materialize, decoded)
    if not ok then
        return nil, tostring(decoded)
    end

    if decoded == nil then
        return nil, err
    end

    return decoded
end


local function qjson_encode(data)
    local ok, encoded, err = pcall(qjson.encode, data)
    if not ok then
        return nil, tostring(encoded)
    end

    return encoded, err
end


function _M.decode(str)
    if not configured_name then
        configured_name = config_local.local_conf().apisix.request_body_json_lib
    end

    local name = configured_name
    if name == "cjson" then
        return core_json.decode(str)
    end

    if name == "simdjson" then
        return simdjson_parser:decode(str)
    end

    return qjson_decode(str)
end


function _M.encode(data)
    if not configured_name then
        configured_name = config_local.local_conf().apisix.request_body_json_lib
    end

    if configured_name == "qjson" then
        return qjson_encode(data)
    end

    -- simdjson encode is slower than cjson, so simdjson mode only uses it for decode.
    return core_json.encode(data)
end


return _M
