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
local require = require
local core = require("apisix.core")
local metrics = require("apisix.stream.xrpc.metrics")
local ipairs = ipairs
local pairs = pairs
local ngx_exit = ngx.exit


local is_http = true
local runner
if ngx.config.subsystem ~= "http" then
    is_http = false
    runner = require("apisix.stream.xrpc.runner")
end

local _M = {}
local registered_protocols = {}
local registered_protocol_schemas = {}


-- only need to load schema module when it is used in Admin API
local function register_protocol(name, is_http)
    if not is_http then
        registered_protocols[name] = require("apisix.stream.xrpc.protocols." .. name)
    end

    registered_protocol_schemas[name] =
        require("apisix.stream.xrpc.protocols." .. name .. ".schema")
end


function _M.init()
    local local_conf = core.config.local_conf()
    if not local_conf.xrpc then
        return
    end

    local prot_conf = local_conf.xrpc.protocols
    if not prot_conf then
        return
    end

    if is_http and not local_conf.apisix.enable_admin then
        -- we need to register xRPC protocols in HTTP only when Admin API is enabled
        return
    end

    for _, prot in ipairs(prot_conf) do
        core.log.info("register xprc protocol ", prot.name)
        register_protocol(prot.name, is_http)
    end
end


function _M.init_metrics(collector)
    local local_conf = core.config.local_conf()
    if not local_conf.xrpc then
        return
    end

    local prot_conf = local_conf.xrpc.protocols
    if not prot_conf then
        return
    end

    for _, prot in ipairs(prot_conf) do
        metrics.store(collector, prot.name)
    end
end


function _M.init_worker()
    for name, prot in pairs(registered_protocols) do
        if not is_http and prot.init_worker then
            prot.init_worker()
        end
    end
end


function _M.check_schema(item, skip_disabled_plugin)
    local name = item.name
    local protocol = registered_protocol_schemas[name]
    if not protocol and not skip_disabled_plugin then
        -- like plugins, ignore unknown plugin if the schema is checked in the DP
        return false, "unknown protocol [" .. name .. "]"
    end

    -- check protocol-specific configuration
    if not item.conf then
        return true
    end
    return protocol.check_schema(item.conf)
end


function _M.run_protocol(conf, ctx)
    local name = conf.name
    local protocol = registered_protocols[name]
    local code = runner.run(protocol, ctx)
    return ngx_exit(code)
end


return _M
