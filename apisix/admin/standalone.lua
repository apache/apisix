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
local ngx_time     = ngx.time
local ngx_now      = ngx.now
local ngx_sleep    = ngx.sleep
local get_method   = ngx.req.get_method
local worker_count = ngx.worker.count
local timer_every  = ngx.timer.every
local exiting      = ngx.worker.exiting
local yaml         = require("lyaml")
local events       = require("apisix.events")
local core         = require("apisix.core")
local config_yaml  = require("apisix.core.config_yaml")
local config_validate = require("apisix.admin.config_validate")

local shared_dict        = ngx.shared["standalone-config"]
local status_shared_dict = ngx.shared["standalone-status"]

local ALL_RESOURCE_KEYS    = config_validate.get_all_resource_keys()
local HTTP_RESOURCE_KEYS   = config_validate.get_http_resource_keys()
local STREAM_RESOURCE_KEYS = config_validate.get_stream_resource_keys()
local APPLIED_CHECK_KEYS = {}
for key in pairs(ALL_RESOURCE_KEYS) do
    if key ~= "plugins" then
        APPLIED_CHECK_KEYS[key] = true
    end
end

local EVENT_UPDATE = "standalone-api-configuration-update"
local NOT_FOUND_ERR = "not found"
-- do not use the HTTP standard Last-Modified header to prevent affecting
-- the caching implementation in the client
local METADATA_LAST_MODIFIED = "X-Last-Modified"
local METADATA_DIGEST = "X-Digest"

local _M = {}

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

local validate_configuration = config_validate.validate_configuration


local MAX_WAIT_MS = 60000
local POLL_INTERVAL = 0.05


local function parse_wait_ms(ctx)
    local args = core.request.get_uri_args(ctx)
    local wait = args and tonumber(args.wait)
    if not wait or wait <= 0 then
        return 0
    end
    if wait > MAX_WAIT_MS then
        return MAX_WAIT_MS
    end
    return wait
end


local function stream_enabled()
    local local_conf = core.config.local_conf()
    return local_conf and local_conf.apisix and local_conf.apisix.stream_proxy
end


local function all_workers_applied(target_digest)
    if not status_shared_dict then
        return false
    end

    local n = worker_count()
    local check_stream = stream_enabled()
    for key in pairs(APPLIED_CHECK_KEYS) do
        for id = 0, n - 1 do
            if HTTP_RESOURCE_KEYS[key] then
                local http_key = "worker:" .. id .. ":http:" .. key
                local digest = status_shared_dict:get(http_key)
                if digest ~= target_digest then
                    core.log.debug("not yet applied: ", http_key, " has ", digest, ", want ", target_digest)
                    return false
                end
            end
            if check_stream and STREAM_RESOURCE_KEYS[key] then
                local stream_key = "worker:" .. id .. ":stream:" .. key
                local digest = status_shared_dict:get(stream_key)
                if digest ~= target_digest then
                    core.log.debug("not yet applied: ", stream_key, " has ", digest, ", want ", target_digest)
                    return false
                end
            end
        end
    end
    return true
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
    if err and err ~= NOT_FOUND_ERR then
        core.log.error("failed to get config from shared dict: ", err)
        return core.response.exit(500, {
            error_msg = "failed to get config from shared dict: " .. err
        })
    end

    -- if the client passes in the same digest, the configuration is not updated
    if config and config[METADATA_DIGEST] == digest then
        -- accepted but not modified because digest is the same
        core.log.info("config not changed: same digest")
        return core.response.exit(204)
    end

    local valid, error_msg = validate_configuration(req_body, false)
    if not valid then
        return core.response.exit(400, { error_msg = error_msg })
    end

    -- check input by jsonschema and build the final config
    local apisix_yaml = {}

    for key, conf_version_key in pairs(ALL_RESOURCE_KEYS) do
        local conf_version = config and config[conf_version_key] or 0
        local items = req_body[key]
        local new_conf_version = req_body[conf_version_key]

        if new_conf_version then
            if new_conf_version < conf_version then
                return core.response.exit(400, {
                    error_msg = conf_version_key ..
                        " must be greater than or equal to (" .. conf_version .. ")",
                })
            end
        else
            new_conf_version = conf_version + 1
        end

        apisix_yaml[conf_version_key] = new_conf_version
        if new_conf_version == conf_version then
            apisix_yaml[key] = config and config[key]
        elseif items and #items > 0 then
            apisix_yaml[key] = items
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

    local wait_ms = parse_wait_ms(ctx)
    if wait_ms <= 0 then
        return core.response.exit(202)
    end

    local deadline = ngx_now() + wait_ms / 1000
    while not exiting() and ngx_now() < deadline do
        if all_workers_applied(digest) then
            return core.response.exit(200)
        end
        ngx_sleep(POLL_INTERVAL)
    end

    return core.response.exit(202)
end

local function get(ctx)
    local accept = core.request.header(nil, "accept") or "application/json"
    local want_yaml_resp = core.string.has_prefix(accept, "application/yaml")

    local config, err = get_config()
    if not config then
        if err ~= NOT_FOUND_ERR then
            core.log.error("failed to get config from shared_dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared_dict: " .. err
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
            core.log.error("failed to get config from shared_dict: ", err)
            return core.response.exit(500, {
                error_msg = "failed to get config from shared_dict: " .. err
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
    end

    if method == "post" then
        local path = ctx.var.uri
        if path == "/apisix/admin/configs/validate" then
            return config_validate.validate()
        else
            return core.response.exit(404, {error_msg = "Not found"})
        end
    end

    if method == "head" then
        return head(ctx)
    end

    return get(ctx)
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

        config_yaml._update_config(config)
    end
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)

    -- due to the event module can not broadcast events between http and stream subsystems,
    -- we need to poll the shared dict to keep the config in sync
    -- The timestamp only has second resolution, so two updates landing in the
    -- same second are indistinguishable by it and the later one would never
    -- reach this worker. The digest changes with the content, so compare both.
    local last_modified_per_worker, digest_per_worker
    timer_every(1, function ()
        if not exiting() then
            local config, err = get_config()
            if not config then
                if err ~= NOT_FOUND_ERR then
                    core.log.error("failed to get config: ", err)
                end
            else
                local last_modified = config[METADATA_LAST_MODIFIED]
                local digest = config[METADATA_DIGEST]
                if last_modified_per_worker ~= last_modified
                   or digest_per_worker ~= digest then
                    update_config(config)
                    last_modified_per_worker = last_modified
                    digest_per_worker = digest
                end
            end
        end
    end)

    patch_schema()
end


return _M
