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
local route = require("apisix.utils.router")
local plugin = require("apisix.plugin")
local ngx = ngx
local get_method = ngx.req.get_method
local ngx_time = ngx.time
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id
local tonumber = tonumber
local str_lower = string.lower
local reload_event = "/apisix/admin/plugins/reload"
local ipairs = ipairs
local error = error
local type = type
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data

local events
local MAX_REQ_BODY = 1024 * 1024 * 1.5      -- 1.5 MiB


local viewer_methods = {
    get = true,
}


local resources = {
    routes          = require("apisix.admin.routes"),
    services        = require("apisix.admin.services"),
    upstreams       = require("apisix.admin.upstreams"),
    consumers       = require("apisix.admin.consumers"),
    schema          = require("apisix.admin.schema"),
    ssl             = require("apisix.admin.ssl"),
    plugins         = require("apisix.admin.plugins"),
    proto           = require("apisix.admin.proto"),
    global_rules    = require("apisix.admin.global_rules"),
    stream_routes   = require("apisix.admin.stream_routes"),
    plugin_metadata = require("apisix.admin.plugin_metadata"),
}


local _M = {version = 0.4}
local router


local function check_token(ctx)
    local local_conf = core.config.local_conf()
    if not local_conf or not local_conf.apisix
       or not local_conf.apisix.admin_key then
        return true
    end

    local req_token = ctx.var.arg_api_key or ctx.var.http_x_api_key
                      or ctx.var.cookie_x_api_key
    if not req_token then
        return false, "missing apikey"
    end

    local admin
    for i, row in ipairs(local_conf.apisix.admin_key) do
        if req_token == row.key then
            admin = row
            break
        end
    end

    if not admin then
        return false, "wrong apikey"
    end

    if admin.role == "viewer" and
       not viewer_methods[str_lower(get_method())] then
        return false, "invalid method for role viewer"
    end

    return true
end


local function strip_etcd_resp(data)
    if type(data) == "table"
        and data.header ~= nil
        and data.header.revision ~= nil
        and data.header.raft_term ~= nil
    then
        -- strip etcd data
        data.header = nil
        data.responses = nil
        data.succeeded = nil

        if data.node then
            data.node.createdIndex = nil
            data.node.modifiedIndex = nil
        end
    end

    return data
end


local function run()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local uri_segs = core.utils.split_uri(ngx.var.uri)
    core.log.info("uri: ", core.json.delay_encode(uri_segs))

    -- /apisix/admin/schema/route
    local seg_res, seg_id = uri_segs[4], uri_segs[5]
    local seg_sub_path = core.table.concat(uri_segs, "/", 6)
    if seg_res == "schema" and seg_id == "plugins" then
        -- /apisix/admin/schema/plugins/limit-count
        seg_res, seg_id = uri_segs[5], uri_segs[6]
        seg_sub_path = core.table.concat(uri_segs, "/", 7)
    end

    local resource = resources[seg_res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    local req_body, err = core.request.get_body(MAX_REQ_BODY)
    if err then
        core.log.error("failed to read request body: ", err)
        core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    local uri_args = ngx.req.get_uri_args() or {}
    if uri_args.ttl then
        if not tonumber(uri_args.ttl) then
            core.response.exit(400, {error_msg = "invalid argument ttl: "
                                                 .. "should be a number"})
        end
    end

    local code, data = resource[method](seg_id, req_body, seg_sub_path,
                                        uri_args)
    if code then
        data = strip_etcd_resp(data)
        core.response.exit(code, data)
    end
end


local function run_stream()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local local_conf = core.config.local_conf()
    if not local_conf.apisix.stream_proxy then
        core.log.warn("stream mode is disabled, can not to add any stream ",
                      "route")
        core.response.exit(400)
    end

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local uri_segs = core.utils.split_uri(ngx.var.uri)
    core.log.info("uri: ", core.json.delay_encode(uri_segs))

    -- /apisix/admin/schema/route
    local seg_res, seg_id = uri_segs[4], uri_segs[5]
    local seg_sub_path = core.table.concat(uri_segs, "/", 6)
    if seg_res == "schema" and seg_id == "plugins" then
        -- /apisix/admin/schema/plugins/limit-count
        seg_res, seg_id = uri_segs[5], uri_segs[6]
        seg_sub_path = core.table.concat(uri_segs, "/", 7)
    end

    local resource = resources[seg_res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    req_read_body()
    local req_body = req_get_body_data()

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    local uri_args = ngx.req.get_uri_args() or {}
    if uri_args.ttl then
        if not tonumber(uri_args.ttl) then
            core.response.exit(400, {error_msg = "invalid argument ttl: "
                                                 .. "should be a number"})
        end
    end

    local code, data = resource[method](seg_id, req_body, seg_sub_path,
                                        uri_args)
    if code then
        data = strip_etcd_resp(data)
        core.response.exit(code, data)
    end
end


local function get_plugins_list()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local plugins = resources.plugins.get_plugins_list()
    core.response.exit(200, plugins)
end


local function post_reload_plugins()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local success, err = events.post(reload_event, get_method(), ngx_time())
    if not success then
        core.response.exit(500, err)
    end

    core.response.exit(200, success)
end


local function sync_local_conf_to_etcd()
    core.log.warn("sync local conf to etcd")

    local local_conf = core.config.local_conf()

    local plugins = {}
    for _, name in ipairs(local_conf.plugins) do
        core.table.insert(plugins, {
            name = name,
        })
    end

    for _, name in ipairs(local_conf.stream_plugins) do
        core.table.insert(plugins, {
            name = name,
            stream = true,
        })
    end

    -- need to store all plugins name into one key so that it can be updated atomically
    local res, err = core.etcd.set("/plugins", plugins)
    if not res then
        core.log.error("failed to set plugins: ", err)
    end
end


local function reload_plugins(data, event, source, pid)
    core.log.info("start to hot reload plugins")
    plugin.load()

    if ngx_worker_id() == 0 then
        sync_local_conf_to_etcd()
    end
end


local uri_route = {
    {
        paths = [[/apisix/admin/*]],
        methods = {"GET", "PUT", "POST", "DELETE", "PATCH"},
        handler = run,
    },
    {
        paths = [[/apisix/admin/stream_routes/*]],
        methods = {"GET", "PUT", "POST", "DELETE", "PATCH"},
        handler = run_stream,
    },
    {
        paths = [[/apisix/admin/plugins/list]],
        methods = {"GET"},
        handler = get_plugins_list,
    },
    {
        paths = reload_event,
        methods = {"PUT"},
        handler = post_reload_plugins,
    },
}


function _M.init_worker()
    local local_conf = core.config.local_conf()
    if not local_conf.apisix or not local_conf.apisix.enable_admin then
        return
    end

    router = route.new(uri_route)
    events = require("resty.worker.events")

    events.register(reload_plugins, reload_event, "PUT")

    if ngx_worker_id() == 0 then
        local ok, err = ngx_timer_at(0, function(premature)
            if premature then
                return
            end

            sync_local_conf_to_etcd()
        end)

        if not ok then
            error("failed to sync local configure to etcd: " .. err)
        end
    end
end


function _M.get()
    return router
end


return _M
