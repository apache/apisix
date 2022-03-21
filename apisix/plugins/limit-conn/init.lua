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
local limit_conn_new = require("resty.limit.conn").new
local core = require("apisix.core")
local sleep = core.sleep
local shdict_name = "plugin-limit-conn"
if ngx.config.subsystem == "stream" then
    shdict_name = shdict_name .. "-stream"
end


local lrucache = core.lrucache.new({
    type = "plugin",
})
local _M = {}


local function create_limit_obj(conf)
    core.log.info("create new limit-conn plugin instance")
    return limit_conn_new(shdict_name, conf.conn, conf.burst,
                          conf.default_conn_delay)
end


function _M.increase(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local lim, err = lrucache(conf, nil, create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.conn object: ", err)
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
    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        -- When the value of key is empty, use client IP instead
        key = ctx.var["remote_addr"]
    end

    key = key .. ctx.conf_type .. ctx.conf_version
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code or 503
        end

        core.log.error("failed to limit conn: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    if lim:is_committed() then
        if not ctx.limit_conn then
            ctx.limit_conn = core.tablepool.fetch("plugin#limit-conn", 0, 6)
        end

        core.table.insert_tail(ctx.limit_conn, lim, key, delay, conf.only_use_default_delay)
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end


function _M.decrease(conf, ctx)
    local limit_conn = ctx.limit_conn
    if not limit_conn then
        return
    end

    for i = 1, #limit_conn, 4 do
        local lim = limit_conn[i]
        local key = limit_conn[i + 1]
        local delay = limit_conn[i + 2]
        local use_delay =  limit_conn[i + 3]

        local latency
        if not use_delay then
            if ctx.proxy_passed then
                latency = ctx.var.upstream_response_time
            else
                latency = ctx.var.request_time - delay
            end
        end
        core.log.debug("request latency is ", latency) -- for test

        local conn, err = lim:leaving(key, latency)
        if not conn then
            core.log.error("failed to record the connection leaving request: ",
                           err)
            break
        end
    end

    core.tablepool.release("plugin#limit-conn", limit_conn)
    ctx.limit_conn = nil
    return
end


return _M
