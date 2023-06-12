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
local support_wasm, wasm = pcall(require, "resty.proxy-wasm")
local ngx_var = ngx.var


local schema = {
    type = "object",
    properties = {
        conf = {
            type = "string",
            minLength = 1,
        },
    },
    required = {"conf"}
}
local _M = {}


local function check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_plugin_ctx_key(ctx)
    return ctx.conf_type .. "#" .. ctx.conf_id
end

local function fetch_plugin_ctx(conf, ctx, plugin)
    if not conf.plugin_ctxs then
        conf.plugin_ctxs = {}
    end

    local ctxs = conf.plugin_ctxs
    local key = get_plugin_ctx_key(ctx)
    local plugin_ctx = ctxs[key]
    local err
    if not plugin_ctx then
        plugin_ctx, err = wasm.on_configure(plugin, conf.conf)
        if not plugin_ctx then
            return nil, err
        end

        ctxs[key] = plugin_ctx
    end

    return plugin_ctx
end


local function http_request_wrapper(self, conf, ctx)
    local name = self.name
    local plugin_ctx, err = fetch_plugin_ctx(conf, ctx, self.plugin)
    if not plugin_ctx then
        core.log.error(name, ": failed to fetch wasm plugin ctx: ", err)
        return 503
    end

    local ok, err = wasm.on_http_request_headers(plugin_ctx)
    if not ok then
        core.log.error(name, ": failed to run wasm plugin: ", err)
        return 503
    end

    -- $wasm_process_req_body is predefined in ngx_tpl.lua
    local handle_body = ngx_var.wasm_process_req_body
    if handle_body ~= '' then
        -- reset the flag so we can use it for the next Wasm plugin
        -- use ngx.var to bypass the cache
        ngx_var.wasm_process_req_body = ''

        local body, err = core.request.get_body()
        if err ~= nil then
            core.log.error(name, ": failed to get request body: ", err)
            return 503
        end

        local ok, err = wasm.on_http_request_body(plugin_ctx, body, true)
        if not ok then
            core.log.error(name, ": failed to run wasm plugin: ", err)
            return 503
        end
    end
end


local function header_filter_wrapper(self, conf, ctx)
    local name = self.name
    local plugin_ctx, err = fetch_plugin_ctx(conf, ctx, self.plugin)
    if not plugin_ctx then
        core.log.error(name, ": failed to fetch wasm plugin ctx: ", err)
        return 503
    end

    local ok, err = wasm.on_http_response_headers(plugin_ctx)
    if not ok then
        core.log.error(name, ": failed to run wasm plugin: ", err)
        return 503
    end

    -- $wasm_process_resp_body is predefined in ngx_tpl.lua
    local handle_body = ngx_var.wasm_process_resp_body
    if handle_body ~= '' then
        -- reset the flag so we can use it for the next Wasm plugin
        -- use ngx.var to bypass the cache
        ngx_var.wasm_process_resp_body = ""
        ctx["wasm_" .. name .. "_process_resp_body"] = true
    end
end


local function body_filter_wrapper(self, conf, ctx)
    local name = self.name

    local enabled = ctx["wasm_" .. name .. "_process_resp_body"]
    if not enabled then
        return
    end

    local plugin_ctx, err = fetch_plugin_ctx(conf, ctx, self.plugin)
    if not plugin_ctx then
        core.log.error(name, ": failed to fetch wasm plugin ctx: ", err)
        return
    end

    local ok, err = wasm.on_http_response_body(plugin_ctx)
    if not ok then
        core.log.error(name, ": failed to run wasm plugin: ", err)
        return
    end
end


function _M.require(attrs)
    if not support_wasm then
        return nil, "need to build APISIX-Base to support wasm"
    end

    local name = attrs.name
    local priority = attrs.priority
    local plugin, err = wasm.load(name, attrs.file)
    if not plugin then
        return nil, err
    end

    local mod = {
        version = 0.1,
        name = name,
        priority = priority,
        schema = schema,
        check_schema = check_schema,
        plugin = plugin,
        type = "wasm",
    }

    if attrs.http_request_phase == "rewrite" then
        mod.rewrite = function (conf, ctx)
            return http_request_wrapper(mod, conf, ctx)
        end
    else
        mod.access = function (conf, ctx)
            return http_request_wrapper(mod, conf, ctx)
        end
    end

    mod.header_filter = function (conf, ctx)
        return header_filter_wrapper(mod, conf, ctx)
    end

    mod.body_filter = function (conf, ctx)
        return body_filter_wrapper(mod, conf, ctx)
    end

    -- the returned values need to be the same as the Lua's 'require'
    return true, mod
end


return _M
