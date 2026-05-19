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


local DEFAULT_JSON_LIB = "qjson"
local json_libs = {
    cjson = true,
    qjson = true,
    simdjson = true,
}

local qjson
local simdjson_parser
local qjson_unavailable
local simdjson_unavailable
local configured_name
local warned_invalid_json_lib
local warned_load_failure = {}

local _M = {}


local function configured_json_lib()
    if configured_name then
        return configured_name
    end

    local local_conf = config_local.local_conf()
    local name = local_conf and local_conf.apisix
                 and local_conf.apisix.request_body_json_lib
                 or DEFAULT_JSON_LIB

    if not json_libs[name] then
        if not warned_invalid_json_lib then
            warned_invalid_json_lib = true
            log.warn("invalid apisix.request_body_json_lib: ", name,
                     ", fallback to ", DEFAULT_JSON_LIB)
        end
        name = DEFAULT_JSON_LIB
    end

    configured_name = name
    return configured_name
end


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
    local name = configured_json_lib()
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

    return normalize_result(pcall(mod.decode, str))
end


function _M.encode(data)
    if configured_json_lib() == "qjson" then
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
