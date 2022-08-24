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
local limit_count = require("apisix.plugins.limit-count.init")

local plugin_name = "limit-count"
local _M = {
    version = 0.4,
    priority = 1002,
    name = plugin_name,
    schema = limit_count.schema,
}


function _M.check_schema(conf)
    return limit_count.check_schema(conf)
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local lim, err
    if not conf.group then
        lim, err = core.lrucache.plugin_ctx(lrucache, ctx, conf.policy, create_limit_obj, conf)
    else
        lim, err = lrucache(conf.group, "", create_limit_obj, conf)
    end

    if not lim then
        core.log.error("failed to fetch limit.count object: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    local conf_key = conf.key
    local key
    if conf.key_type == "var_combination" then
        local err, n_resolved
        key, err, n_resolved = core.utils.resolve_var(conf_key, ctx.var)
        if err then
            core.log.error("could not resolve vars in ", conf_key, " error: ", err)
        end

        if n_resolved == 0 then
            key = nil
        end
    elseif conf.key_type == "constant" then
        key = conf_key
    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        -- When the value of key is empty, use client IP instead
        key = ctx.var["remote_addr"]
    end

    -- here we add a separator ':' to mark the boundary of the prefix and the key itself
    if not conf.group then
        -- Here we use plugin-level conf version to prevent the counter from being resetting
        -- because of the change elsewhere.
        -- A route which reuses a previous route's ID will inherits its counter.
        key = ctx.conf_type .. apisix_plugin.conf_version(conf) .. ':' .. key
    else
        key = conf.group .. ':' .. key
    end

    core.log.info("limit key: ", key)

    local delay, remaining = lim:incoming(key, true)
    if not delay then
        local err = remaining
        if err == "rejected" then
            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code
        end

        core.log.error("failed to limit count: ", err)
        if conf.allow_degradation then
            return
        end
        return 500, {error_msg = "failed to limit count"}
    end

    if conf.show_limit_quota_header then
        core.response.set_header("X-RateLimit-Limit", conf.count,
            "X-RateLimit-Remaining", remaining)
    end
end


return _M
