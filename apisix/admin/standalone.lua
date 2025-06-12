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
local type         = type
local pairs        = pairs
local ipairs       = ipairs
local str_lower    = string.lower
local ngx          = ngx
local get_method   = ngx.req.get_method
local shared_dict  = ngx.shared["standalone-config"]
local table_insert = table.insert
local table_new    = require("table.new")
local yaml         = require("lyaml")
local events       = require("apisix.events")
local core         = require("apisix.core")
local config_yaml  = require("apisix.core.config_yaml")
local check_schema = require("apisix.core.schema").check
local tbl_deepcopy = require("apisix.core.table").deepcopy

local EVENT_UPDATE = "standalone-api-configuration-update"

local _M = {}

local function check_duplicate(item, key, id_set)
    local identifier, identifier_type
    if key == "consumer" then
        identifier = item.username
        identifier_type = "username"
    else
        identifier = item.id
        identifier_type = "id"
    end

    if not identifier then
        return
    end

    if id_set[identifier] then
        return "duplicate " .. identifier_type .. " found " .. identifier
    end
    id_set[identifier] = true
end

local function get_config()
    local config = shared_dict:get("config")
    if not config then
        return nil, "not found"
    end

    local err
    config, err = core.json.decode(config)
    if not config then
        return nil, "failed to decode json: " .. err
    end
    return config
end


local function update_and_broadcast_config(apisix_yaml)
    local raw, err = core.json.encode(apisix_yaml)
    if not raw then
        core.log.error("failed to encode json: ", err)
        return nil, "failed to encode json: " .. err
    end

    if shared_dict then
        -- the worker that handles Admin API calls is responsible for writing the shared dict
        local ok, err = shared_dict:set("config", raw)
        if not ok then
            return nil, "failed to save config to shared dict: " .. err
        end
        core.log.info("standalone config updated: ", raw)
    else
        core.log.crit(config_yaml.ERR_NO_SHARED_DICT)
    end
    return events:post(EVENT_UPDATE, EVENT_UPDATE)
end


local function update(ctx)
    local content_type = core.request.header(nil, "content-type") or "application/json"

    -- read the request body
    local req_body, err = core.request.get_body()
    if err then
        return core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    if not req_body or #req_body <= 0 then
        return core.response.exit(400, {error_msg = "invalid request body: empty request body"})
    end

    -- parse the request body
    local data
    if core.string.has_prefix(content_type, "application/yaml") then
        data = yaml.load(req_body, { all = false })
        if not data or type(data) ~= "table" then
            err = "invalid yaml request body"
        end
    else
        data, err = core.json.decode(req_body)
    end
    if err then
        core.log.error("invalid request body: ", req_body, " err: ", err)
        core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end
    req_body = data

    local config, err = get_config()
    if not config then
        if err ~= "not found" then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared dict: " .. err
            })
        end
    end

    -- check input by jsonschema
    local apisix_yaml = {}
    local created_objs = config_yaml.fetch_all_created_obj()

    for key, obj in pairs(created_objs) do
        local conf_version_key = obj.conf_version_key
        local conf_version = config and config[conf_version_key] or obj.conf_version
        local items = req_body[key]
        local new_conf_version = req_body[conf_version_key]
        if not new_conf_version then
            new_conf_version = conf_version + 1
        else
            if type(new_conf_version) ~= "number" then
                return core.response.exit(400, {
                    error_msg = conf_version_key .. " must be a number",
                })
            end
            if new_conf_version < conf_version then
                return core.response.exit(400, {
                    error_msg = conf_version_key ..
                        " must be greater than or equal to (" .. conf_version .. ")",
                })
            end
        end

        apisix_yaml[conf_version_key] = new_conf_version
        if new_conf_version == conf_version then
            apisix_yaml[key] = config and config[key]
        elseif items and #items > 0 then
            apisix_yaml[key] = table_new(#items, 0)
            local item_schema = obj.item_schema
            local item_checker = obj.checker
            local id_set = {}

            for index, item in ipairs(items) do
                local item_temp = tbl_deepcopy(item)
                local valid, err
                -- need to recover to 0-based subscript
                local err_prefix = "invalid " .. key .. " at index " .. (index - 1) .. ", err: "
                if item_schema then
                    valid, err = check_schema(obj.item_schema, item_temp)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err})
                    end
                end
                if item_checker then
                    local item_checker_key
                    if item.id then
                        -- credential need to check key
                        item_checker_key = "/" .. key .. "/" .. item_temp.id
                    end
                    valid, err = item_checker(item_temp, item_checker_key)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err})
                    end
                end
                -- check duplicate resource
                local err = check_duplicate(item, key, id_set)
                if err then
                    core.log.error(err_prefix, err)
                    core.response.exit(400, { error_msg = err_prefix .. err })
                end

                table_insert(apisix_yaml[key], item)
            end
        end
    end

    local ok, err = update_and_broadcast_config(apisix_yaml)
    if not ok then
        core.response.exit(500, err)
    end

    return core.response.exit(202)
end


local function get(ctx)
    local accept = core.request.header(nil, "accept") or "application/json"
    local want_yaml_resp = core.string.has_prefix(accept, "application/yaml")

    local config, err = get_config()
    if not config then
        if err ~= "not found" then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared dict: " .. err
            })
        end
        config = {}
        local created_objs = config_yaml.fetch_all_created_obj()
        for _, obj in pairs(created_objs) do
            config[obj.conf_version_key] = obj.conf_version
        end
    end

    local resp, err
    if want_yaml_resp then
        core.response.set_header("Content-Type", "application/yaml")
        resp = yaml.dump({ config })
        if not resp then
            err = "failed to encode yaml"
        end

        -- remove the first line "---" and the last line "..."
        -- because the yaml.dump() will add them for multiple documents
        local m = ngx.re.match(resp, [[^---\s*([\s\S]*?)\s*\.\.\.\s*$]], "jo")
        if m and m[1] then
            resp = m[1]
        end
    else
        core.response.set_header("Content-Type", "application/json")
        resp, err = core.json.encode(config, true)
        if not resp then
            err = "failed to encode json: " .. err
        end
    end

    if not resp then
        return core.response.exit(500, {error_msg = err})
    end
    return core.response.exit(200, resp)
end


function _M.run()
    local ctx = ngx.ctx.api_ctx
    local method = str_lower(get_method())
    if method == "put" then
        return update(ctx)
    else
        return get(ctx)
    end
end


local patch_schema
do
    local resource_schema = {
        "proto",
        "global_rule",
        "route",
        "service",
        "upstream",
        "consumer",
        "consumer_group",
        "credential",
        "ssl",
        "plugin_config",
    }
    local function attach_modifiedIndex_schema(name)
        local schema = core.schema[name]
        if not schema then
            core.log.error("schema for ", name, " not found")
            return
        end
        if schema.properties and not schema.properties.modifiedIndex then
            schema.properties.modifiedIndex = {
                type = "integer",
            }
        end
    end

    local function patch_credential_schema()
        local credential_schema = core.schema["credential"]
        if credential_schema and credential_schema.properties then
            credential_schema.properties.id = {
                type = "string",
                minLength = 15,
                maxLength = 128,
                pattern = [[^[a-zA-Z0-9-_]+/credentials/[a-zA-Z0-9-_.]+$]],
            }
        end
    end

    function patch_schema()
        -- attach modifiedIndex schema to all resource schemas
        for _, name in ipairs(resource_schema) do
            attach_modifiedIndex_schema(name)
        end
        -- patch credential schema
        patch_credential_schema()
    end
end


function _M.init_worker()
    local function update_config()
        local config, err = shared_dict:get("config")
        if not config then
            core.log.error("failed to get config from shared dict: ", err)
            return
        end

        config, err = core.json.decode(config)
        if not config then
            core.log.error("failed to decode json: ", err)
            return
        end
        config_yaml._update_config(config)
    end
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)

    patch_schema()
end


return _M
