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
local tonumber     = tonumber
local tostring     = tostring
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



local function get_config()
    local config, err = shared_dict:get("config")
    if not config then
        return nil, "not found"
    end

    config, err = core.json.decode(config)
    if not config then
        return nil, "failed to decode json: " .. err
    end
    return config
end


local function update_and_broadcast_config(old_config, apisix_yaml, conf_version_kv)
    local config = {
        conf = apisix_yaml,
        conf_version = conf_version_kv
    }

    if old_config then
        local ori_config = tbl_deepcopy(old_config)
        ori_config.conf_version = ori_config.conf_version or {}
        ori_config.conf = ori_config.conf or {}
        for key, v in pairs(conf_version_kv) do
            if v ~= ori_config.conf_version[key] then
                ori_config.conf[key] = apisix_yaml[key]
                ori_config.conf_version[key] = v
            end
        end
        config = ori_config
    end

    local encoded_config, encode_err = core.json.encode(config)
    if not encoded_config then
        core.log.error("failed to encode json: ", encode_err)
        return nil, "failed to encode json: " .. encode_err
    end

    if shared_dict then
        local ok, save_err = shared_dict:set("config", encoded_config)
        if not ok then
            return nil, "failed to save config to shared dict: " .. save_err
        end
        core.log.info("standalone config updated: ", encoded_config)
    else
        core.log.crit(config_yaml.ERR_NO_SHARED_DICT)
    end
    return events:post(EVENT_UPDATE, EVENT_UPDATE)
end


local function update(ctx)
    local content_type = core.request.header(nil, "content-type") or "application/json"


    local update_keys

    local config, err = get_config()
    if not config then
        if err ~= "not found" then
            core.log.error("failed to get config from shared dict: ", err)
            return core.response.exit(500, {error_msg = "failed to get config from shared dict: " .. err})
        end
    else
        for key, version in pairs(config.conf_version) do
            local header = "x-apisix-conf-version" .. "-" .. key
            local req_conf_version = core.request.header(ctx, header)
            if req_conf_version then
                if not tonumber(req_conf_version) then
                    return core.response.exit(400, {error_msg = "invalid header: [" .. header ..
                        ": " .. req_conf_version .. "]" ..
                        " should be a integer"})
                end
                req_conf_version = tonumber(req_conf_version)
                if req_conf_version <= version then
                    return core.response.exit(400, {error_msg = "invalid header: [" .. header ..
                        ": " .. req_conf_version .. "]" ..
                        " should be greater than the current version (" .. version .. ")"})
                else
                    update_keys = update_keys or {}
                    update_keys[key] = req_conf_version
                end
            end
        end
    end

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

    -- check input by jsonschema
    local apisix_yaml = {}
    local confi_version_kv = tbl_deepcopy(config and config.conf_version or {})
    local created_objs = config_yaml.fetch_all_created_obj()

    for key, obj in pairs(created_objs) do
        local updated = false
        if not update_keys then
            confi_version_kv[key] = confi_version_kv[key] and confi_version_kv[key] + 1 or 1
            updated = true
        elseif update_keys[key] then
            confi_version_kv[key] = update_keys[key]
            updated = true
        end
        if updated and req_body[key] and #req_body[key] > 0 then
            apisix_yaml[key] = table_new(1, 0)
            local item_schema = obj.item_schema
            local item_checker = obj.checker

            for index, item in ipairs(req_body[key]) do
                local valid, err
                -- need to recover to 0-based subscript
                local err_prefix = "invalid " .. key .. " at index " .. (index - 1) .. ", err: "
                if item_schema then
                    valid, err = check_schema(obj.item_schema, item)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err})
                    end
                end
                if item_checker then
                    valid, err = item_checker(item)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err})
                    end
                end
                table_insert(apisix_yaml[key], item)
            end
        end
    end

    local ok, err = update_and_broadcast_config(config, apisix_yaml, confi_version_kv)
    if not ok then
        core.response.exit(500, err)
    end

    for key, version in pairs(confi_version_kv) do
        core.response.set_header("X-APISIX-Conf-Version-" .. key, tostring(version))
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
            return core.response.exit(500, {error_msg = "failed to get config from shared dict: " .. err})
        end
        config = {}
        local created_objs = config_yaml.fetch_all_created_obj()
        for _, obj in pairs(created_objs) do
            core.response.set_header("X-APISIX-Conf-Version-" .. obj.key, tostring(obj.conf_version))
        end
    else
        for key, version in pairs(config.conf_version) do
            core.response.set_header("X-APISIX-Conf-Version-" .. key, tostring(version))
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


function _M.init_worker()
    local function update_config(data, event, resource, pid)
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
        config_yaml._update_config(config.conf, config.conf_version)
    end
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)
end


return _M
