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
local ngx             = ngx
local get_headers     = ngx.req.get_headers

local plugin_name = "authz-casbin"

local schema = {
    type = "object",
    properties = {
        model_path = { type = "string" },
        policy_path = { type = "string" },
        model = { type = "string" },
        policy = { type = "string" },
        username = { type = "string"}
    },
    oneOf = {
        {required = {"model_path", "policy_path", "username"}},
        {required = {"model", "policy", "username"}}
    },
}

local metadata_schema = {
    type = "object",
    properties = {
        model = {type = "string"},
        policy = {type = "string"},
    },
    required = {"model", "policy"},
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
        if metadata and metadata.value and conf.username then
            return true
        end
    end
    return false, err
end

local casbin_enforcer

local function new_enforcer_if_need(conf)
    if conf.model_path and conf.policy_path then
        local model_path = conf.model_path
        local policy_path = conf.policy_path
        if not conf.casbin_enforcer then
            conf.casbin_enforcer = casbin:new(model_path, policy_path)
        end
        return true
    end

    if conf.model and conf.policy then
        local model = conf.model
        local policy = conf.policy
        if not conf.casbin_enforcer then
            conf.casbin_enforcer = casbin:newEnforcerFromText(model, policy)
        end
        return true
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    if not (metadata and metadata.value.model and metadata.value.policy) then
        return nil, "not enough configuration to create enforcer"
    end

    local modifiedIndex = metadata.modifiedIndex
    if not casbin_enforcer or casbin_enforcer.modifiedIndex ~= modifiedIndex then
        local model = metadata.value.model
        local policy = metadata.value.policy
        casbin_enforcer = casbin:newEnforcerFromText(model, policy)
        casbin_enforcer.modifiedIndex = modifiedIndex
    end
    return true
end


function _M.rewrite(conf, ctx)
    -- creates an enforcer when request sent for the first time
    local ok, err = new_enforcer_if_need(conf)
    if not ok then
        return 503, {message = err}
    end

    local path = ctx.var.uri
    local method = ctx.var.method
    local username = get_headers()[conf.username] or "anonymous"

    if conf.casbin_enforcer then
        if not conf.casbin_enforcer:enforce(username, path, method) then
            return 403, {message = "Access Denied"}
        end
    else
        if not casbin_enforcer:enforce(username, path, method) then
            return 403, {message = "Access Denied"}
        end
    end
end



return _M
