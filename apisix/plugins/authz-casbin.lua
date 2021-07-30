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
        local ok, err = core.schema.check(metadata_schema, conf)
        if ok then
            casbin_enforcer = nil
            return true
        else
            return false, err
        end
    end
    local ok, err = core.schema.check(schema, conf)
    if ok then
        casbin_enforcer = nil
        return true
    else
        local metadata = plugin.plugin_metadata(plugin_name)
        if metadata and metadata.value.model and metadata.value.policy and conf.username then
            casbin_enforcer = nil
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


return _M
