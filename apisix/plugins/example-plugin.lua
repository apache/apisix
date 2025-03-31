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
local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local upstream = require("apisix.upstream")
local http = require("resty.http")
local lua_proxy_request = require("apisix.lua_proxy").request
local plugin_lua_body_filter = require("apisix.lua_proxy").lua_body_filter

local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR

local schema = {
    type = "object",
    properties = {
        i = {type = "number", minimum = 0},
        s = {type = "string"},
        t = {type = "array", minItems = 1},
        ip = {type = "string"},
        port = {type = "integer"},
    },
    required = {"i"},
}

local metadata_schema = {
    type = "object",
    properties = {
        ikey = {type = "number", minimum = 0},
        skey = {type = "string"},
    },
    required = {"ikey", "skey"},
}

local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


function _M.init()
    -- call this function when plugin is loaded
    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        core.log.info(plugin_name, " get plugin attr val: ", attr.val)
    end
end


function _M.destroy()
    -- call this function when plugin is unloaded
end


function _M.rewrite(conf, ctx)
    core.log.warn("plugin rewrite phase, conf: ", core.json.encode(conf))
    core.log.warn("conf_type: ", ctx.conf_type)
    core.log.warn("conf_id: ", ctx.conf_id)
    core.log.warn("conf_version: ", ctx.conf_version)
end


function _M.access(conf, ctx)
    core.log.warn("plugin access phase, conf: ", core.json.encode(conf))
    -- return 200, {message = "hit example plugin"}

    if conf.lua_proxy_upstream then
        ctx.lua_proxy_upstream = true
    end

    if not conf.ip then
        return
    end

    local up_conf = {
        type = "roundrobin",
        nodes = {
            {host = conf.ip, port = conf.port, weight = 1}
        }
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        return HTTP_INTERNAL_SERVER_ERROR, err
    end

    local matched_route = ctx.matched_route
    upstream.set(ctx, up_conf.type .. "#route_" .. matched_route.value.id,
                 ctx.conf_version, up_conf)
    return
end


function _M.before_proxy(conf, ctx)
    core.log.warn("plugin before_proxy phase, conf: ", core.json.encode(conf))

    if ctx.lua_proxy_upstream then
        local status, body = lua_proxy_request(conf, ctx)
        if status ~= 200 then
            return status, body
        end
        core.log.warn("lua proxy upstream response: ", core.json.encode(body))
        plugin_lua_body_filter(conf, ctx, body)
    end
end


function _M.lua_body_filter(conf, ctx, body)
    core.log.warn("plugin lua_body_filter phase, conf: ", core.json.encode(conf))
    core.log.warn("plugin lua_body_filter phase, body: ", core.json.encode(body))

    local httpc, err = http.new()
    if err then
        core.log.error("failed to create http client: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local res, err = httpc:request_uri(conf.request_uri, {
        method = conf.method,
    })
    if err then
        core.log.error("failed to request in lua_body_filter: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local res_body, err = core.json.decode(res.body)
    if err then
        core.log.error("failed to decode response body: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    return res.status, res_body
end


function _M.header_filter(conf, ctx)
    core.log.warn("plugin header_filter phase, conf: ", core.json.encode(conf))
end


function _M.body_filter(conf, ctx)
    core.log.warn("plugin body_filter phase, eof: ", ngx.arg[2],
                  ", conf: ", core.json.encode(conf))
end


function _M.delayed_body_filter(conf, ctx)
    core.log.warn("plugin delayed_body_filter phase, eof: ", ngx.arg[2],
                  ", conf: ", core.json.encode(conf))
end

function _M.log(conf, ctx)
    core.log.warn("plugin log phase, conf: ", core.json.encode(conf))
end


local function hello()
    local args = ngx.req.get_uri_args()
    if args["json"] then
        return 200, {msg = "world"}
    else
        return 200, "world\n"
    end
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris = {"/v1/plugin/example-plugin/hello"},
            handler = hello,
        }
    }
end


return _M
