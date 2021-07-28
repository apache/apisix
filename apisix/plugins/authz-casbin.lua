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

local casbin          = require("casbin")
local core            = require("apisix.core")
local plugin          = require("apisix.plugin")
local plugin_metadata = require("apisix.admin.plugin_metadata")
local ngx             = ngx
local get_headers     = ngx.req.get_headers

local casbin_enforcer

local plugin_name = "authz-casbin"

local schema = {
    type = "object",
    properties = {
        model_path = { type = "string" },
        policy_path = { type = "string" },
        username = { type = "string"}
    },
    required = {"model_path", "policy_path", "username"},
    additionalProperties = false
}

local metadata_schema = {
    type = "object",
    properties = {
        model = {type = "string"},
        policy = {type = "string"},
    },
    required = {"model", "policy"},
    additionalProperties = false
}

local _M = {
    version = 0.1,
    priority = 2560,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    local ok, err = core.schema.check(schema, conf)
    if ok then
        return true
    else
        local metadata = plugin.plugin_metadata(plugin_name)
        if metadata and metadata.value.model and metadata.value.policy and conf.username then
            return true
        end
    end
    return false, err
end


local function new_enforcer(model_path, policy_path)
    local e

    if model_path and policy_path then
        e = casbin:new(model_path, policy_path)
        e.type = "file"
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    if metadata and metadata.value.model and metadata.value.policy then
        local model = metadata.value.model
        local policy = metadata.value.policy
        e = casbin:newEnforcerFromText(model, policy)
        e.type = "metadata"
    end

    return e
end


function _M.rewrite(conf)
    -- creates an enforcer when request sent for the first time
    if not casbin_enforcer then
        casbin_enforcer = new_enforcer(conf.model_path, conf.policy_path)
    end

    local path = ngx.var.request_uri
    local method = ngx.var.request_method
    local username = get_headers()[conf.username]
    if not username then username = "anonymous" end

    if path and method and username then
        if not casbin_enforcer:enforce(username, path, method) then
            return 403, {message = "Access Denied"}
        end
    else
        return 403, {message = "Access Denied"}
    end
end


local function save_policy()
    if not casbin_enforcer then
        return 400, {message = "Enforcer not created yet."}
    end

    if casbin_enforcer.type == "metadata" then
        local metadata = plugin.plugin_metadata(plugin_name)
        local conf = {
            model = metadata.value.model,
            policy = casbin_enforcer.model:savePolicyToText()
        }

        local ok, err = plugin_metadata.put(plugin_name, conf)
        if not ok then
            core.log.error("Save Policy error: " .. err)
            return 400, {message = "Failed to save policy, see logs."}
        else
            return 200
        end
    else
        local _, err = pcall(function ()
            casbin_enforcer:savePolicy()
        end)
        if not err then
            return 200, {message = "Successfully saved policy."}
        else
            core.log.error("Save Policy error: " .. err)
            return 400, {message = "Failed to save policy, see logs."}
        end
    end
end


local function add_policy()
    if not casbin_enforcer then
        return 400, {message = "Enforcer not created yet."}
    end

    local headers = get_headers()
    local type = headers["type"]

    if type == "p" then
        local subject = headers["subject"]
        local object = headers["object"]
        local action = headers["action"]

        if not subject or not object or not action then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:AddPolicy(subject, object, action) then
            local ok, _ = save_policy()
            if ok == 400 then
                return 400, {message = "Failed to save policy, see logs."}
            end
            return 200, {message = "Successfully added policy."}
        else
            return 400, {message = "Invalid policy request."}
        end
    elseif type == "g" then
        local user = headers["user"]
        local role = headers["role"]

        if not user or not role then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:AddGroupingPolicy(user, role) then
            local ok, _ = save_policy()
            if ok == 400 then
                return 400, {message = "Failed to save policy, see logs."}
            end
            return 200, {message = "Successfully added grouping policy."}
        else
            return 400, {message = "Invalid policy request."}
        end
    else
        return 400, {message = "Invalid policy type."}
    end
end


local function remove_policy()
    if not casbin_enforcer then
        return 400, {message = "Enforcer not created yet."}
    end

    local headers = get_headers()
    local type = headers["type"]

    if type == "p" then
        local subject = headers["subject"]
        local object = headers["object"]
        local action = headers["action"]

        if not subject or not object or not action then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:RemovePolicy(subject, object, action) then
            local ok, _ = save_policy()
            if ok == 400 then
                return 400, {message = "Failed to save policy, see logs."}
            end
            return 200, {message = "Successfully removed policy."}
        else
            return 400, {message = "Invalid policy request."}
        end
    elseif type == "g" then
        local user = headers["user"]
        local role = headers["role"]

        if not user or not role then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:RemoveGroupingPolicy(user, role) then
            local ok, _ = save_policy()
            if ok == 400 then
                return 400, {message = "Failed to save policy, see logs."}
            end
            return 200, {message = "Successfully removed grouping policy."}
        else
            return 400, {message = "Invalid policy request."}
        end
    else
        return 400, {message = "Invalid policy type."}
    end
end


local function has_policy()
    if not casbin_enforcer then
        return 400, {message = "Enforcer not created yet."}
    end

    local headers = get_headers()
    local type = headers["type"]

    if type == "p" then
        local subject = headers["subject"]
        local object = headers["object"]
        local action = headers["action"]

        if not subject or not object or not action then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:HasPolicy(subject, object, action) then
            return 200, {data = "true"}
        else
            return 200, {data = "false"}
        end
    elseif type == "g" then
        local user = headers["user"]
        local role = headers["role"]

        if not user or not role then
            return 400, {message = "Invalid policy request."}
        end

        if casbin_enforcer:HasGroupingPolicy(user, role) then
            return 200, {data = "true"}
        else
            return 200, {data = "false"}
        end
    else
        return 400, {message = "Invalid policy type."}
    end
end


local function get_policy()
    if not casbin_enforcer then
        return 400, {message = "Enforcer not created yet."}
    end

    local headers = get_headers()
    local type = headers["type"]

    if type == "p" then
        local policy = casbin_enforcer:GetPolicy()
        if policy then
            return 200, {data = policy}
        else
            return 400
        end
    elseif type == "g" then
        local groupingPolicy = casbin_enforcer:GetGroupingPolicy()
        if groupingPolicy then
            return 200, {data = groupingPolicy}
        else
            return 400
        end
    else
        return 400, {message = "Invalid policy type."}
    end
end


function _M.api()
    return {
        {
            methods = {"POST"},
            uri = "/apisix/plugin/authz-casbin/add",
            handler = add_policy,
        },
        {
            methods = {"POST"},
            uri = "/apisix/plugin/authz-casbin/remove",
            handler = remove_policy,
        },
        {
            methods = {"GET"},
            uri = "/apisix/plugin/authz-casbin/has",
            handler = has_policy,
        },
        {
            methods = {"GET"},
            uri = "/apisix/plugin/authz-casbin/get",
            handler = get_policy,
        },
        {
            methods = {"POST"},
            uri = "/apisix/plugin/authz-casbin/save",
            handler = save_policy,
        },
        }
end


return _M