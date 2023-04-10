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
local core          = require("apisix.core")
local url           = require("net.url")

local math_random = math.random
local has_mod, apisix_ngx_client = pcall(require, "resty.apisix.client")


local plugin_name   = "proxy-mirror"
local schema = {
    type = "object",
    properties = {
        host = {
            type = "string",
            pattern = [=[^http(s)?:\/\/([\da-zA-Z.-]+|\[[\da-fA-F:]+\])(:\d+)?$]=],
        },
        path = {
            type = "string",
            pattern = [[^/[^?&]+$]],
        },
        path_concat_mode = {
            type = "string",
            default = "replace",
            enum = {"replace", "prefix"},
            description = "the concatenation mode for custom path"
        },
        sample_ratio = {
            type = "number",
            minimum = 0.00001,
            maximum = 1,
            default = 1,
        },
    },
    required = {"host"},
}

local _M = {
    version = 0.1,
    priority = 1010,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function resolver_host(prop_host)
    local url_decoded = url.parse(prop_host)
    local decoded_host = url_decoded.host
    if not core.utils.parse_ipv4(decoded_host) and not core.utils.parse_ipv6(decoded_host) then
        local ip, err = core.resolver.parse_domain(decoded_host)

        if not ip then
            core.log.error("dns resolver resolves domain: ", decoded_host," error: ", err,
                            " will continue to use the host: ", decoded_host)
            return prop_host
        end

        local host = url_decoded.scheme .. '://' .. ip ..
            (url_decoded.port and ':' .. url_decoded.port or '')
        core.log.info(prop_host, " is resolved to: ", host)
        return host
    end
    return prop_host
end


local function enable_mirror(ctx, conf)
    local uri = (ctx.var.upstream_uri and ctx.var.upstream_uri ~= "") and
                ctx.var.upstream_uri or
                ctx.var.uri .. ctx.var.is_args .. (ctx.var.args or '')

    if conf.path then
        if conf.path_concat_mode == "prefix" then
            uri = conf.path .. uri
        else
            uri = conf.path .. ctx.var.is_args .. (ctx.var.args or '')
        end
    end

    ctx.var.upstream_mirror_uri = resolver_host(conf.host) .. uri

    if has_mod then
        apisix_ngx_client.enable_mirror()
    end
end


function _M.rewrite(conf, ctx)
    core.log.info("proxy mirror plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    if conf.sample_ratio == 1 then
        enable_mirror(ctx, conf)
    else
        local val = math_random()
        core.log.info("mirror request sample_ratio conf: ", conf.sample_ratio,
                                ", random value: ", val)
        if val < conf.sample_ratio then
            enable_mirror(ctx, conf)
        end
    end

end


return _M
