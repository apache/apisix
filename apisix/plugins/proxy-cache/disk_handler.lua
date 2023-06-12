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

local os = os
local ngx_re = require("ngx.re")
local core = require("apisix.core")
local util = require("apisix.plugins.proxy-cache.util")

local _M = {}


local function disk_cache_purge(conf, ctx)
    local cache_zone_info = ngx_re.split(ctx.var.upstream_cache_zone_info, ",")

    local filename = util.generate_cache_filename(cache_zone_info[1], cache_zone_info[2],
        ctx.var.upstream_cache_key)

    if util.file_exists(filename) then
        os.remove(filename)
        return nil
    end

    return "Not found"
end


function _M.access(conf, ctx)
    ctx.var.upstream_cache_zone = conf.cache_zone

    if ctx.var.request_method == "PURGE" then
        local err = disk_cache_purge(conf, ctx)
        if err ~= nil then
            return 404
        end

        return 200
    end

    if conf.cache_bypass ~= nil then
        local value = util.generate_complex_value(conf.cache_bypass, ctx)
        ctx.var.upstream_cache_bypass = value
        core.log.info("proxy-cache cache bypass value:", value)
    end

    if not util.match_method(conf, ctx) then
        ctx.var.upstream_cache_bypass = "1"
        core.log.info("proxy-cache cache bypass method: ", ctx.var.request_method)
    end
end


function _M.header_filter(conf, ctx)
    local no_cache = "1"

    if util.match_method(conf, ctx) and util.match_status(conf, ctx) then
        no_cache = "0"
    end

    if conf.no_cache ~= nil then
        local value = util.generate_complex_value(conf.no_cache, ctx)
        core.log.info("proxy-cache no-cache value:", value)

        if value ~= nil and value ~= "" and value ~= "0" then
            no_cache = "1"
        end
    end

    local upstream_hdr_cache_control
    local upstream_hdr_expires

    if conf.hide_cache_headers == true then
        upstream_hdr_cache_control = ""
        upstream_hdr_expires = ""
    else
        upstream_hdr_cache_control = ctx.var.upstream_http_cache_control
        upstream_hdr_expires = ctx.var.upstream_http_expires
    end

    core.response.set_header("Cache-Control", upstream_hdr_cache_control,
        "Expires", upstream_hdr_expires,
        "Apisix-Cache-Status", ctx.var.upstream_cache_status)

    ctx.var.upstream_no_cache = no_cache
    core.log.info("proxy-cache no cache:", no_cache)
end


return _M
