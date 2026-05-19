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
local log = require("apisix.core.log")
local core_json = require("apisix.core.json")
local require = require
local pcall = pcall


local qjson
local simdjson_parser
local qjson_unavailable
local simdjson_unavailable
local configured_name
local warned_load_failure = {}

local _M = {}


local function normalize_result(ok, res, err)
    if not ok then
        return nil, res
    end

    return res, err
end


local function qjson_module()
    if qjson then
        return qjson
    end

    if qjson_unavailable then
        return nil, qjson_unavailable
    end

    local ok, mod = pcall(require, "qjson")
    if not ok then
        qjson_unavailable = "failed to load qjson: " .. mod
        return nil, qjson_unavailable
    end

    qjson = mod
    return qjson
end


local function warn_load_failure(name, err)
    if warned_load_failure[name] then
        return
    end

    warned_load_failure[name] = true
    log.warn(err, ", fallback to cjson")
end


local function simdjson_decode(str)
    if simdjson_unavailable then
        return nil, simdjson_unavailable, true
    end

    if not simdjson_parser then
        local ok, simdjson = pcall(require, "resty.simdjson")
        if not ok then
            simdjson_unavailable = "failed to load simdjson: " .. simdjson
            return nil, simdjson_unavailable, true
        end

        local parser, err = simdjson.new()
        if not parser then
            simdjson_unavailable = "failed to create simdjson parser: "
                                  .. (err or "unknown")
            return nil, simdjson_unavailable, true
        end
        simdjson_parser = parser
    end

    return normalize_result(pcall(simdjson_parser.decode, simdjson_parser, str))
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
        local res, err, can_fallback = simdjson_decode(str)
        if can_fallback then
            warn_load_failure(name, err)
            return core_json.decode(str)
        end

        return res, err
    end

    local mod, err = qjson_module()
    if not mod then
        warn_load_failure(name, err)
        return core_json.decode(str)
    end

    local decoded, err = normalize_result(pcall(mod.decode, str))
    if not decoded then
        return nil, err
    end

    return normalize_result(pcall(mod.materialize, decoded))
end


function _M.encode(data)
    if not configured_name then
        configured_name = config_local.local_conf().apisix.request_body_json_lib
    end

    if configured_name == "qjson" then
        local mod, err = qjson_module()
        if not mod then
            warn_load_failure("qjson", err)
            return normalize_result(pcall(core_json.encode, data))
        end

        return normalize_result(pcall(mod.encode, data))
    end

    return normalize_result(pcall(core_json.encode, data))
end


return _M
