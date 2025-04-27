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
local str_lower    = string.lower
local ngx          = ngx
local get_method   = ngx.req.get_method
local table_insert = table.insert
local table_new    = require("table.new")
local yaml         = require("lyaml")
local events       = require("apisix.events")
local core         = require("apisix.core")
local config_yaml  = require("apisix.core.config_yaml")
local event        = require("apisix.core.event")
local check_schema = require("apisix.core.schema").check

local EVENT_UPDATE = "standalone-api-configuration-update"

local _M = {}


local function update(ctx)
    local content_type = core.request.header(nil, "content-type")
    local is_json_request = content_type and core.string.has_prefix(content_type, "application/json") or true
    local is_yaml_request = content_type and core.string.has_prefix(content_type, "application/yaml") or false

    if not is_json_request and not is_yaml_request then
        core.response.exit(400, {error_msg = "invalid content type: " .. content_type ..
                                             ", should be application/json or application/yaml" })
    end

    local conf_version
    if ctx.var.arg_conf_version then
        conf_version = tonumber(ctx.var.arg_conf_version)
        if not conf_version then
            core.response.exit(400, {error_msg = "invalid conf_version: " .. ctx.var.arg_conf_version
                                          .. ", should be a integer" })
        end
    else
        conf_version = ngx.time()
    end

    -- read the request body
    local req_body, err = core.request.get_body()
    if err then
        core.log.error("failed to read request body: ", err)
        core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    -- parse the request body
    if req_body then
        local data, err
        if is_json_request then
            data, err = core.json.decode(req_body)
        elseif is_yaml_request then
            data = yaml.load(req_body, { all = false })
            if not data or type(data) ~= "table" then
                err = "invalid yaml request body"
            end
        end
        if err then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body: " .. err,
                                     req_body = req_body})
        end

        req_body = data
    end

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
                local err_prefix = "invalid " .. key .. " at index " .. index .. ", err: "
                if item_schema then
                    valid, err = check_schema(obj.item_schema, item)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err,
                                                req_body = req_body})
                    end
                end
                if item_checker then
                    valid, err = item_checker(item)
                    if not valid then
                        core.log.error(err_prefix, err)
                        core.response.exit(400, {error_msg = err_prefix .. err,
                                                req_body = req_body})
                    end
                end
                table_insert(apisix_yaml[key], item)
            end
        end
    end

    local success, err = events:post(EVENT_UPDATE, EVENT_UPDATE, core.json.encode({
        config = apisix_yaml,
        conf_version = conf_version,
    }))
    if not success then
        core.response.exit(500, err)
    end

    return core.response.exit(202)
end


local function get(ctx)
    local accept = core.request.header(nil, "accept")
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
    if str_lower(get_method()) == "put" then
        return update(ctx)
    else
        return get(ctx)
    end
end


function _M.init_worker()
    local function update_config(data)
        local data, err = core.json.decode(data)
        if not data then
            core.log.error("failed to decode json: ", err)
            return
        end
        config_yaml._update_config(data.config, data.conf_version)
    end
    events:register(update_config, EVENT_UPDATE, EVENT_UPDATE)
end


return _M
