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
local is_apisix_or, client = pcall(require, "resty.apisix.client")
local str_byte = string.byte
local str_sub = string.sub
local type = type


local schema = {
    type = "object",
    properties = {
        source = {
            type = "string",
            minLength = 1
        }
    },
    required = {"source"},
}


local plugin_name = "real-ip"


local _M = {
    version = 0.1,
    priority = 23000,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_addr(conf, ctx)
    if conf.source == "http_x_forwarded_for" then
        -- use the last address from X-Forwarded-For header
        local addrs = core.request.header(ctx, "X-Forwarded-For")
        if not addrs then
            return nil
        end

        if type(addrs) == "table" then
            addrs = addrs[#addrs]
        end

        local idx = core.string.rfind_char(addrs, ",")
        if not idx then
            return addrs
        end

        for i = idx + 1, #addrs do
            if str_byte(addrs, i) == str_byte(" ") then
                idx = idx + 1
            else
                break
            end
        end

        return str_sub(addrs, idx + 1)
    end
    return ctx.var[conf.source]
end


function _M.rewrite(conf, ctx)
    if not is_apisix_or then
        core.log.error("need to build APISIX-OpenResty to support setting real ip")
        return 501
    end

    local addr = get_addr(conf, ctx)
    if not addr then
        core.log.warn("missing real address")
        return
    end

    local ip, port = core.utils.parse_addr(addr)
    if not ip or (not core.utils.parse_ipv4(ip) and not core.utils.parse_ipv6(ip)) then
        core.log.warn("bad address: ", addr)
        return
    end

    if str_byte(ip, 1, 1) == str_byte("[") then
        -- For IPv6, the `set_real_ip` accepts '::1' but not '[::1]'
        ip = str_sub(ip, 2, #ip - 1)
    end

    if port ~= nil and (port < 1 or port > 65535) then
        core.log.warn("bad port: ", port)
        return
    end

    core.log.info("set real ip: ", ip, ", port: ", port)

    local ok, err = client.set_real_ip(ip, port)
    if not ok then
        core.log.error("failed to set real ip: ", err)
        return
    end

    -- flush cached vars in APISIX
    ctx.var.remote_addr = nil
    ctx.var.remote_port = nil
    ctx.var.realip_remote_addr = nil
    ctx.var.realip_remote_port = nil
end


return _M
