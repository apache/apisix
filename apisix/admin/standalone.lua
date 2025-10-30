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
local str_find     = string.find
local str_sub      = string.sub
local tostring     = tostring
local ngx          = ngx
local ngx_time     = ngx.time
local get_method   = ngx.req.get_method
local shared_dict  = ngx.shared["standalone-config"]
local timer_every  = ngx.timer.every
local exiting      = ngx.worker.exiting
local table_insert = table.insert
local table_new    = require("table.new")
local yaml         = require("lyaml")
local events       = require("apisix.events")
local core         = require("apisix.core")
local config_yaml  = require("apisix.core.config_yaml")
local tbl_deepcopy = require("apisix.core.table").deepcopy
local constants    = require("apisix.constants")

-- combine all resources that using in http and stream substreams as one constant
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

local EVENT_UPDATE = "standalone-api-configuration-update"
local NOT_FOUND_ERR = "not found"
-- do not use the HTTP standard Last-Modified header to prevent affecting
-- the caching implementation in the client
local METADATA_LAST_MODIFIED = "X-Last-Modified"
local METADATA_DIGEST = "X-Digest"

local _M = {}

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

local function check_duplicate(item, key, id_set)
    local identifier, identifier_type
    if key == "consumers" then
        identifier = item.id or item.username
        identifier_type = item.id and "credential id" or "username"
    else
        identifier = item.id
        identifier_type = "id"
    end

    if id_set[identifier] then
        return true, "found duplicate " .. identifier_type .. " " .. identifier .. " in " .. key
    end
    id_set[identifier] = true
    return false
end

local function get_config()
    local config = shared_dict:get("config")
    if not config then
        return nil, NOT_FOUND_ERR
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

local function validate(ctx)
    local content_type = core.request.header(nil, "content-type") or "application/json"
    local req_body, err = core.request.get_body()
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
        core.log.error("invalid request body: ", req_body, " err: ", err)
        return core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end
    req_body = data

    local validation_results = {
        valid = true,
        errors = {}
    }


    for key, conf_version_key in pairs(ALL_RESOURCE_KEYS) do
        local items = req_body[key]
        local resource = resources[key] or {}

        if items and #items > 0 then
            local item_schema = resource.schema
            local item_checker = resource.checker
            local id_set = {}

            for index, item in ipairs(items) do
                local item_temp = tbl_deepcopy(item)
                local valid, err = check_conf(item_checker, item_schema, item_temp, key)
                if not valid then
                    local err_prefix = "invalid " .. key .. " at index " .. (index - 1) .. ", err: "
                    local err_msg = type(err) == "table" and err.error_msg or err

                    validation_results.valid = false
                    table_insert(validation_results.errors, {
                        resource_type = key,
                        index = index - 1,
                        error = err_prefix .. err_msg
                    })
                end

                -- check for duplicate IDs
                local duplicated, dup_err = check_duplicate(item, key, id_set)
                if duplicated then
                    validation_results.valid = false
                    table_insert(validation_results.errors, {
                        resource_type = key,
                        index = index - 1,
                        error = dup_err
                    })
                end
            end
        end

        -- Validate conf_version_key if present
        local new_conf_version = req_body[conf_version_key]
        if new_conf_version and type(new_conf_version) ~= "number" then
            validation_results.valid = false
            table_insert(validation_results.errors, {
                resource_type = key,
                error = conf_version_key .. " must be a number, got " .. type(new_conf_version)
            })
        end
    end


    if validation_results.valid then
        return core.response.exit(200, {
            message = "Configuration is valid",
            valid = true
        })
    else
        return core.response.exit(400, {
            error_msg = "Configuration validation failed",
            valid = false,
            errors = validation_results.errors
        })
    end
end


local function update(ctx)
    -- check digest header existence
    local digest = core.request.header(nil, METADATA_DIGEST)
    if not digest then
        return core.response.exit(400, {
            error_msg = "missing digest header"
        })
    end

    -- read the request body
    local content_type = core.request.header(nil, "content-type") or "application/json"
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
        if err ~= NOT_FOUND_ERR then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared dict: " .. err
            })
        end
    end

    -- if the client passes in the same digest, the configuration is not updated
    if config and config[METADATA_DIGEST] == digest then
        -- accepted but not modified because digest is the same
        core.log.info("config not changed: same digest")
        return core.response.exit(204)
    end

    -- check input by jsonschema
    local apisix_yaml = {}

    for key, conf_version_key in pairs(ALL_RESOURCE_KEYS) do
        local conf_version = config and config[conf_version_key] or 0
        local items = req_body[key]
        local new_conf_version = req_body[conf_version_key]
        local resource = resources[key] or {}
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
            local item_schema = resource.schema
            local item_checker = resource.checker
            local id_set = {}

            for index, item in ipairs(items) do
                local item_temp = tbl_deepcopy(item)
                local valid, err = check_conf(item_checker, item_schema, item_temp, key)
                if not valid then
                    local err_prefix = "invalid " .. key .. " at index " .. (index - 1) .. ", err: "
                    local err_msg = type(err) == "table" and err.error_msg or err
                    core.response.exit(400, { error_msg = err_prefix .. err_msg })
                end
                -- prevent updating resource with the same ID
                -- (e.g., service ID or other resource IDs) in a single request
                local duplicated, err = check_duplicate(item, key, id_set)
                if duplicated then
                    core.log.error(err)
                    core.response.exit(400, { error_msg = err })
                end

                table_insert(apisix_yaml[key], item)
            end
        end
    end

    -- write metadata
    apisix_yaml[METADATA_LAST_MODIFIED] = ngx_time()
    apisix_yaml[METADATA_DIGEST] = digest

    local ok, err = update_and_broadcast_config(apisix_yaml)
    if not ok then
        core.response.exit(500, err)
    end

    core.response.set_header(METADATA_LAST_MODIFIED, apisix_yaml[METADATA_LAST_MODIFIED])
    core.response.set_header(METADATA_DIGEST, apisix_yaml[METADATA_DIGEST])
    return core.response.exit(202)
end


local function get(ctx)
    local accept = core.request.header(nil, "accept") or "application/json"
    local want_yaml_resp = core.string.has_prefix(accept, "application/yaml")

    local config, err = get_config()
    if not config then
        if err ~= NOT_FOUND_ERR then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared dict: " .. err
            })
        end
        config = {}
        for _, conf_version_key in pairs(ALL_RESOURCE_KEYS) do
            config[conf_version_key] = 0
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

    core.response.set_header(METADATA_LAST_MODIFIED, config and config[METADATA_LAST_MODIFIED])
    core.response.set_header(METADATA_DIGEST, config and config[METADATA_DIGEST])
    return core.response.exit(200, resp)
end


local function head(ctx)
    local config, err = get_config()
    if not config then
        if err ~= NOT_FOUND_ERR then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared dict: " .. err
            })
        end
    end

    core.response.set_header(METADATA_LAST_MODIFIED, config and config[METADATA_LAST_MODIFIED])
    core.response.set_header(METADATA_DIGEST, config and config[METADATA_DIGEST])
    return core.response.exit(200)
end


function _M.run()
    local ctx = ngx.ctx.api_ctx
    local method = str_lower(get_method())
    if method == "put" then
        return update(ctx)
    elseif method == "post" then
        local path = ctx.var.uri
        if path == "/apisix/admin/configs/validate" then
            return validate(ctx)
        else
            return core.response.exit(404, {error_msg = "Not found"})
        end
    elseif method == "head" then
        return head(ctx)
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
        "stream_route",
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
    local function update_config(config)
        if not config then
            local err
            config, err = get_config()
            if not config then
                core.log.error("failed to get config: ", err)
                return
            end
        end

        -- remove metadata key in-place
        -- this table is generated by json decode, so there is no need to clone it
        config[METADATA_LAST_MODIFIED] = nil
        config[METADATA_DIGEST] = nil
        config_yaml._update_config(config)
    end
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)

    -- due to the event module can not broadcast events between http and stream subsystems,
    -- we need to poll the shared dict to keep the config in sync
    local last_modified_per_worker
    timer_every(1, function ()
        if not exiting() then
            local config, err = get_config()
            if not config then
                if err ~= NOT_FOUND_ERR then
                    core.log.error("failed to get config: ", err)
                end
            else
                local last_modified = config[METADATA_LAST_MODIFIED]
                if last_modified_per_worker ~= last_modified then
                    update_config(config)
                    last_modified_per_worker = last_modified
                end
            end
        end
    end)

    patch_schema()
end


return _M
