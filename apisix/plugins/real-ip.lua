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
local ngx_re_split = require("ngx.re").split
local is_apisix_or, client = pcall(require, "resty.apisix.client")
local str_byte = string.byte
local str_sub = string.sub
local ipairs = ipairs
local type = type

local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        trusted_addresses = {
            type = "array",
            items = {anyOf = core.schema.ip_def},
            minItems = 1
        },
        source = {
            type = "string",
            minLength = 1
        },
        recursive = {
            type = "boolean",
            default = false
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
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.trusted_addresses then
        for _, cidr in ipairs(conf.trusted_addresses) do
            if not core.ip.validate_cidr_or_ip(cidr) then
                return false, "invalid ip address: " .. cidr
            end
        end
    end
    return true
end


local function addr_match(conf, ctx, addr)
    local matcher, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                  core.ip.create_ip_matcher, conf.trusted_addresses)
    if not matcher then
        core.log.error("failed to create ip matcher: ", err)
        return false
    end

    return matcher:match(addr)
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

        if conf.recursive and conf.trusted_addresses then
            local split_addrs = ngx_re_split(addrs, ",\\s*", "jo")
            for i = #split_addrs, 2, -1 do
                if not addr_match(conf, ctx, split_addrs[i]) then
                    return split_addrs[i]
                end
            end

            return split_addrs[1]
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
        core.log.error("need to build APISIX-Base to support setting real ip")
        return 501
    end

    if conf.trusted_addresses then
        local remote_addr = ctx.var.remote_addr
        if not addr_match(conf, ctx, remote_addr) then
            return
        end
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
