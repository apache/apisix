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
local expr = require("resty.expr.v1")
local core = require("apisix.core")
local apisix_upstream = require("apisix.upstream")
local resource = require("apisix.admin.resource")
local schema_plugin = require("apisix.admin.plugins").check_schema
local type = type
local loadstring = loadstring


local function check_conf(id, conf, need_id, schema)
    if conf.host and conf.hosts then
        return nil, {error_msg = "only one of host or hosts is allowed"}
    end

    if conf.remote_addr and conf.remote_addrs then
        return nil, {error_msg = "only one of remote_addr or remote_addrs is "
                                 .. "allowed"}
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local upstream_conf = conf.upstream
    if upstream_conf then
        local ok, err = apisix_upstream.check_upstream_conf(upstream_conf)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    local upstream_id = conf.upstream_id
    if upstream_id then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    local service_id = conf.service_id
    if service_id then
        local key = "/services/" .. service_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch service info by "
                                     .. "service id [" .. service_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    local plugin_config_id = conf.plugin_config_id
    if plugin_config_id then
        local key = "/plugin_configs/" .. plugin_config_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch plugin config info by "
                                     .. "plugin config id [" .. plugin_config_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch plugin config info by "
                                     .. "plugin config id [" .. plugin_config_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    if conf.vars then
        ok, err = expr.new(conf.vars)
        if not ok then
            return nil, {error_msg = "failed to validate the 'vars' expression: " .. err}
        end
    end

    if conf.filter_func then
        local func, err = loadstring("return " .. conf.filter_func)
        if not func then
            return nil, {error_msg = "failed to load 'filter_func' string: "
                                     .. err}
        end

        if type(func()) ~= "function" then
            return nil, {error_msg = "'filter_func' should be a function"}
        end
    end

    if conf.script then
        local obj, err = loadstring(conf.script)
        if not obj then
            return nil, {error_msg = "failed to load 'script' string: "
                                     .. err}
        end

        if type(obj()) ~= "table" then
            return nil, {error_msg = "'script' should be a Lua object"}
        end
    end

    return true
end


return resource.new({
    name = "routes",
    kind = "route",
    schema = core.schema.route,
    checker = check_conf
})
