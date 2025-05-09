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
local process      = require("ngx.process")
local worker_pid   = ngx.worker.pid

local EVENT_UPDATE = "standalone-api-configuration-update"

local _M = {}


local function sync_status_to_shdict(status)
    local status_shdict = ngx.shared.status_report_standalone
    if process.type() ~= "worker" then
        return
    end
    local pid = worker_pid()
    status_shdict:set(pid, status, 5*60)
end


local function update_and_broadcast_config(apisix_yaml, conf_version)
    local config = core.json.encode({
        conf = apisix_yaml,
        conf_version = conf_version,
    })

    if shared_dict then
        -- the worker that handles Admin API calls is responsible for writing the shared dict
        local ok, err = shared_dict:set("config", config)
        if not ok then
            return nil, "failed to save config to shared dict: " .. err
        end
        core.log.info("standalone config updated: ", config)
    else
        core.log.crit(config_yaml.ERR_NO_SHARED_DICT)
    end
    return events:post(EVENT_UPDATE, EVENT_UPDATE)
end


local function update(ctx)
    local content_type = core.request.header(nil, "content-type") or "application/json"

    local conf_version
    if ctx.var.arg_conf_version then
        conf_version = tonumber(ctx.var.arg_conf_version)
        if not conf_version then
            return core.response.exit(400, {error_msg = "invalid conf_version: "
                                            .. ctx.var.arg_conf_version
                                            .. ", should be a integer" })
        end
    else
        conf_version = ngx.time()
    end
    -- check if conf_version greater than the current version
    local _, ver = config_yaml._get_config()
    if conf_version <= ver then
        return core.response.exit(400, {error_msg = "invalid conf_version: conf_version ("
                                        .. conf_version
                                        .. ") should be greater than the current version ("
                                        .. ver .. ")"})
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
    local created_objs = config_yaml.fetch_all_created_obj()
    for key, obj in pairs(created_objs) do
        if req_body[key] and #req_body[key] > 0 then
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

    local ok, err = update_and_broadcast_config(apisix_yaml, conf_version)
    if not ok then
        core.response.exit(500, err)
    end

    core.response.set_header("X-APISIX-Conf-Version", tostring(conf_version))
    return core.response.exit(202)
end


local function get(ctx)
    local accept = core.request.header(nil, "accept") or "application/json"
    local want_yaml_resp = core.string.has_prefix(accept, "application/yaml")

    local _, ver, config = config_yaml._get_config()

    core.response.set_header("X-APISIX-Conf-Version", tostring(ver))
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
        config_yaml._update_config(config.conf, config.conf_version)
        sync_status_to_shdict(true)
    end
    sync_status_to_shdict(false)
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)
end


return _M
