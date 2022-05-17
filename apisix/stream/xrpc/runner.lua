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
local expr = require("resty.expr.v1")
local pairs = pairs
local ngx = ngx
local ngx_now = ngx.now
local OK = ngx.OK
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE
local pcall = pcall
local ipairs = ipairs
local tostring = tostring


core.ctx.register_var("rpc_time", function(ctx)
    return ctx._rpc_end_time - ctx._rpc_start_time
end)

local logger_expr_cache = core.lrucache.new({
    ttl = 300, count = 1024
})

local _M = {}


local function open_session(conn_ctx)
    conn_ctx.xrpc_session = {
        conn_ctx = conn_ctx,
        route = conn_ctx.matched_route.value,
        -- fields start with '_' should not be accessed by the protocol implementation
        _upstream_conf = conn_ctx.matched_upstream,
        _ctxs = {},
    }
    return conn_ctx.xrpc_session
end


local function put_req_ctx(session, ctx)
    local id = ctx._id
    session._ctxs[id] = nil

    core.ctx.release_vars(ctx)

    core.tablepool.release("xrpc_ctxs", ctx)
end


local function filter_logger(ctx, logger)
    if not logger then
       return false
    end

    if not logger.filter or #logger.filter == 0 then
        -- no valid filter, default execution plugin
        return true
    end

    local version = tostring(logger.filter)
    local filter_expr, err = logger_expr_cache(ctx.conf_id, version, expr.new, logger.filter)
    if not filter_expr or err then
        core.log.error("failed to validate the 'filter' expression: ", err)
        return false
    end
    return filter_expr:eval(ctx.var)
end


local function run_log_plugin(ctx, logger)
    local pkg_name = "apisix.stream.plugins." .. logger.name
    local ok, plugin = pcall(require, pkg_name)
    if not ok then
        core.log.error("failed to load plugin [", logger.name, "] err: ", plugin)
        return
    end

    local log_func = plugin.log
    if log_func then
        log_func(logger.conf, ctx)
    end
end


local function finialize_req(protocol, session, ctx)
    ctx._rpc_end_time = ngx_now()
    local loggers = session.route.protocol.logger
    if loggers and #loggers > 0 then
        for _, logger in ipairs(loggers) do
            ctx.conf_id = tostring(logger.conf)
            local matched = filter_logger(ctx, logger)
            core.log.info("log filter: ", logger.name, " filter result: ", matched)
            if matched then
                run_log_plugin(ctx, logger)
            end
        end
    end

    protocol.log(session, ctx)
    put_req_ctx(session, ctx)
end


local function close_session(session, protocol)
    local upstream_ctx = session._upstream_ctx
    if upstream_ctx then
        upstream_ctx.closed = true

        local up = upstream_ctx.upstream
        protocol.disconnect_upstream(session, up)
    end

    local upstream_ctxs = session._upstream_ctxs
    if upstream_ctxs then
        for _, upstream_ctx in pairs(upstream_ctxs) do
            upstream_ctx.closed = true

            local up = upstream_ctx.upstream
            protocol.disconnect_upstream(session, up)
        end
    end

    for id, ctx in pairs(session._ctxs) do
        core.log.notice("RPC is not finished, id: ", id)
        ctx.unfinished = true
        finialize_req(protocol, session, ctx)
    end
end


local function open_upstream(protocol, session, ctx)
    local key = session._upstream_key
    session._upstream_key = nil

    if key then
        if not session._upstream_ctxs then
            session._upstream_ctxs = {}
        end

        local up_ctx = session._upstream_ctxs[key]
        if up_ctx then
            return OK, up_ctx
        end
    else
        if session._upstream_ctx then
            return OK, session._upstream_ctx
        end

        session.upstream_conf = session._upstream_conf
    end

    local state, upstream = protocol.connect_upstream(session, session)
    if state ~= OK then
        return state, nil
    end

    local up_ctx = {
        upstream = upstream,
        closed = false,
    }
    if key then
        session._upstream_ctxs[key] = up_ctx
    else
        session._upstream_ctx = up_ctx
    end

    return OK, up_ctx
end


local function start_upstream_coroutine(session, protocol, downstream, up_ctx)
    local upstream = up_ctx.upstream
    while not up_ctx.closed do
        local status, ctx = protocol.from_upstream(session, downstream, upstream)
        if status ~= OK then
            if ctx ~= nil then
                finialize_req(protocol, session, ctx)
            end

            if status == DECLINED then
                -- fail to read
                break
            end

            if status == DONE then
                -- a rpc is finished
                goto continue
            end
        end

        ::continue::
    end
end


function _M.run(protocol, conn_ctx)
    local session = open_session(conn_ctx)
    local downstream = protocol.init_downstream(session)

    while true do
        local status, ctx = protocol.from_downstream(session, downstream)
        if status ~= OK then
            if ctx ~= nil then
                finialize_req(protocol, session, ctx)
            end

            if status == DECLINED then
                -- fail to read or can't be authorized
                break
            end

            if status == DONE then
                -- heartbeat or fault injection, already reply to downstream
                goto continue
            end
        end

        -- need to do some auth/routing jobs before reaching upstream
        local status, up_ctx = open_upstream(protocol, session, ctx)
        if status ~= OK then
            if ctx ~= nil then
                finialize_req(protocol, session, ctx)
            end

            break
        end

        status = protocol.to_upstream(session, ctx, downstream, up_ctx.upstream)
        if status ~= OK then
            if ctx ~= nil then
                finialize_req(protocol, session, ctx)
            end

            if status == DECLINED then
                break
            end

            if status == DONE then
                -- for Unary request we can directly reply here
                goto continue
            end
        end

        if not up_ctx.coroutine then
            local co, err = ngx.thread.spawn(
                start_upstream_coroutine, session, protocol, downstream, up_ctx)
            if not co then
                core.log.error("failed to start upstream coroutine: ", err)
                break
            end

            up_ctx.coroutine = co
        end

        ::continue::
    end

    close_session(session, protocol)

    -- return non-zero code to terminal the session
    return 200
end


return _M
