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
local core = require("apisix.core")
local resource = require("apisix.admin.resource")
local schema_plugin = require("apisix.admin.plugins").check_schema
local plugins_encrypt_conf = require("apisix.admin.plugins").encrypt_conf
local global_rules_mod = require("apisix.global_rules")

local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring

local function check_conf(id, conf, need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local ok, err = schema_plugin(conf.plugins)
    if not ok then
        return nil, {error_msg = err}
    end

    -- Check for plugin conflicts with existing global rules
    if conf.plugins then
        local global_rules = global_rules_mod.global_rules()
        core.log.info("dibag global_rules: ", core.json.encode(global_rules))
        if global_rules then
            for _, existing_rule in ipairs(global_rules) do
                -- Skip checking against itself when updating
                if existing_rule.value and existing_rule.value.id and
                   tostring(existing_rule.value.id) ~= tostring(id) then

                    if existing_rule.value.plugins then
                        -- Check for any overlapping plugins
                        for plugin_name, _ in pairs(conf.plugins) do
                            if existing_rule.value.plugins[plugin_name] then
                                return nil, {
                                    error_msg = "plugin '" .. plugin_name ..
                                    "' already exists in global rule with id '" ..
                                    existing_rule.value.id .. "'"
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end


local function encrypt_conf(id, conf)
    plugins_encrypt_conf(conf.plugins)
end


return resource.new({
    name = "global_rules",
    kind = "global rule",
    schema = core.schema.global_rule,
    checker = check_conf,
    encrypt_conf = encrypt_conf,
    unsupported_methods = {"post"}
})
