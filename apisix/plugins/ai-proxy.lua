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
local schema = require("apisix.plugins.ai-proxy.schema")
local base = require("apisix.plugins.ai-proxy.base")

local require = require
local pcall = pcall

local plugin_name = "ai-proxy"
local _M = {
    version = 0.5,
    priority = 1040,
    name = plugin_name,
    schema = schema.ai_proxy_schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema.ai_proxy_schema, conf)
    if not ok then
        return false, err
    end
    local ai_driver, err = pcall(require, "apisix.plugins.ai-drivers." .. conf.provider)
    if not ai_driver then
        core.log.warn("fail to require ai provider: ", conf.provider, ", err", err)
        return false, "ai provider: " .. conf.provider .. " is not supported."
    end
    local sa_json = core.table.try_read_attr(conf, "auth", "gcp", "service_account_json")
    if sa_json then
        local _, err = core.json.decode(sa_json)
        if err then
            return false, "invalid gcp service_account_json: " .. err
        end
    end
    return ok
end


function _M.access(conf, ctx)
    ctx.picked_ai_instance_name = "ai-proxy-" .. conf.provider
    ctx.picked_ai_instance = conf
    ctx.balancer_ip = ctx.picked_ai_instance_name
    ctx.bypass_nginx_upstream = true
end


_M.before_proxy = base.before_proxy

function _M.log(conf, ctx)
    if conf.logging then
        base.set_logging(ctx, conf.logging.summaries, conf.logging.payloads)
    end
end

return _M
