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

--- Batch configuration validation module.
-- Validates APISIX declarative configurations (routes, services, consumers, etc.)
-- including resource-level JSON Schema and plugin check_schema() advanced validation.
-- Used by both standalone mode and etcd mode via POST /apisix/admin/configs/validate.

local type         = type
local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local pcall        = pcall
local str_find     = string.find
local str_sub      = string.sub
local table_insert = table.insert
local yaml         = require("lyaml")
local core         = require("apisix.core")
local tbl_deepcopy = require("apisix.core.table").deepcopy
local constants    = require("apisix.constants")

local _M = {}

-- 1.5 MiB, same as other Admin API handlers
local MAX_REQ_BODY = 1024 * 1024 * 1.5

local resources = {
    routes          = require("apisix.admin.routes"),
    services        = require("apisix.admin.services"),
    upstreams       = require("apisix.admin.upstreams"),
    consumers       = require("apisix.admin.consumers"),
    credentials     = require("apisix.admin.credentials"),
    schema          = require("apisix.admin.schema"),
    ssls            = require("apisix.admin.ssl"),
    plugins         = require("apisix.admin.plugins"),
    protos          = require("apisix.admin.proto"),
    global_rules    = require("apisix.admin.global_rules"),
    stream_routes   = require("apisix.admin.stream_routes"),
    plugin_metadata = require("apisix.admin.plugin_metadata"),
    plugin_configs  = require("apisix.admin.plugin_config"),
    consumer_groups = require("apisix.admin.consumer_group"),
    secrets         = require("apisix.admin.secrets"),
}

local CONF_VERSION_KEY_SUFFIX = "_conf_version"
local ALL_RESOURCE_KEYS = {}
for dir in pairs(constants.HTTP_ETCD_DIRECTORY) do
    local key = str_sub(dir, 2)
    ALL_RESOURCE_KEYS[key] = key .. CONF_VERSION_KEY_SUFFIX
end
for dir in pairs(constants.STREAM_ETCD_DIRECTORY) do
    local key = str_sub(dir, 2)
    ALL_RESOURCE_KEYS[key] = key .. CONF_VERSION_KEY_SUFFIX
end


local function check_duplicate(item, key, id_set)
    local identifier, identifier_type
    if key == "consumers" then
        identifier = item.id or item.username
        identifier_type = item.id and "credential id" or "username"
    else
        identifier = item.id
        identifier_type = "id"
    end

    if not identifier then
        return false
    end

    if id_set[identifier] then
        return true, "found duplicate " .. identifier_type .. " " .. identifier .. " in " .. key
    end
    id_set[identifier] = true
    return false
end


local function check_conf(checker, schema, item, typ)
    if not checker then
        return true
    end
    local str_id = tostring(item.id)
    if typ == "consumers" and
        core.string.find(str_id, "/credentials/") then
        local credential_checker = resources.credentials.checker
        local credential_schema = resources.credentials.schema
        return credential_checker(item.id, item, false, credential_schema, {
            skip_references_check = true,
        })
    end

    local secret_type
    if typ == "secrets" then
        local idx = str_find(str_id or "", "/")
        if not idx then
            return false, {
                error_msg = "invalid secret id: " .. (str_id or "")
            }
        end
        secret_type = str_sub(str_id, 1, idx - 1)
    end
    return checker(item.id, item, false, schema, {
        secret_type = secret_type,
        skip_references_check = true,
    })
end


function _M.validate_configuration(req_body, collect_all_errors)
    local is_valid = true
    local validation_results = {}

    for key, conf_version_key in pairs(ALL_RESOURCE_KEYS) do
        local items = req_body[key]
        local resource = resources[key] or {}

        -- Validate conf_version_key if present
        local new_conf_version = req_body[conf_version_key]
        if new_conf_version and type(new_conf_version) ~= "number" then
            if not collect_all_errors then
                return false, conf_version_key .. " must be a number"
            end
            is_valid = false
            table_insert(validation_results, {
                resource_type = key,
                error = conf_version_key .. " must be a number, got " .. type(new_conf_version)
            })
        end

        if items and #items > 0 then
            local item_schema = resource.schema
            local item_checker = resource.checker
            local id_set = {}

            for index, item in ipairs(items) do
                local item_temp = tbl_deepcopy(item)
                local ok, valid, err = pcall(check_conf, item_checker, item_schema, item_temp, key)
                if not ok then
                    -- checker threw an error
                    err = valid  -- pcall returns (false, error_message)
                    valid = false
                end
                if not valid then
                    local err_prefix = "invalid " .. key .. " at index " .. (index - 1) .. ", err: "
                    local err_msg = type(err) == "table" and err.error_msg or err
                    local error_msg = err_prefix .. tostring(err_msg)

                    if not collect_all_errors then
                        return false, error_msg
                    end
                    is_valid = false
                    table_insert(validation_results, {
                        resource_type = key,
                        index = index - 1,
                        error = error_msg
                    })
                end

                -- check for duplicate IDs
                local duplicated, dup_err = check_duplicate(item, key, id_set)
                if duplicated then
                    if not collect_all_errors then
                        return false, dup_err
                    end
                    is_valid = false
                    table_insert(validation_results, {
                        resource_type = key,
                        index = index - 1,
                        error = dup_err
                    })
                end
            end
        end
    end

    if collect_all_errors then
        return is_valid, validation_results
    end

    return is_valid, nil
end


function _M.validate()
    local content_type = core.request.header(nil, "content-type") or "application/json"
    local req_body, err = core.request.get_body(MAX_REQ_BODY)
    if err then
        return core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    if not req_body or #req_body <= 0 then
        return core.response.exit(400, {error_msg = "invalid request body: empty request body"})
    end

    local data
    if core.string.has_prefix(content_type, "application/yaml") then
        local ok, result = pcall(yaml.load, req_body, { all = false })
        if not ok or type(result) ~= "table" then
            err = "invalid yaml request body"
        else
            data = result
        end
    else
        data, err = core.json.decode(req_body)
    end

    if err then
        core.log.warn("invalid request body: ", req_body, " err: ", err)
        return core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    local ok, valid, validation_results = pcall(_M.validate_configuration, data, true)
    if not ok then
        core.log.warn("unexpected error during validation: ", tostring(valid))
        return core.response.exit(400, {
            error_msg = "Configuration validation failed",
            errors = {{error = tostring(valid)}}
        })
    end
    if not valid then
        -- Ensure all error values in validation_results are JSON-serializable
        for i, item in ipairs(validation_results) do
            if type(item.error) ~= "string" then
                validation_results[i].error = tostring(item.error)
            end
        end
        return core.response.exit(400, {
            error_msg = "Configuration validation failed",
            errors = validation_results
        })
    end

    return core.response.exit(200)
end


function _M.get_all_resource_keys()
    return ALL_RESOURCE_KEYS
end


function _M.get_resources()
    return resources
end


return _M
