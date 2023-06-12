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

--- Upstream helper functions which can be used in xRPC
--
-- @module xrpc.sdk
local core = require("apisix.core")
local config_util = require("apisix.core.config_util")
local router = require("apisix.stream.router.ip_port")
local metrics = require("apisix.stream.xrpc.metrics")
local apisix_upstream = require("apisix.upstream")
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local ngx_now = ngx.now
local str_fmt = string.format
local tab_insert = table.insert
local error = error
local tostring = tostring


local _M = {}


---
-- Returns the connected xRPC upstream socket according to the configuration
--
-- @function xrpc.sdk.connect_upstream
-- @tparam table node selected upstream node
-- @tparam table up_conf upstream configuration
-- @treturn table|nil the xRPC upstream socket, or nil if failed
function _M.connect_upstream(node, up_conf)
    local sk = xrpc_socket.upstream.socket()

    local timeout = up_conf.timeout
    if not timeout then
        -- use the default timeout of Nginx proxy
        sk:settimeouts(60 * 1000, 600 * 1000, 600 * 1000)
    else
        -- the timeout unit for balancer is second while the unit for cosocket is millisecond
        sk:settimeouts(timeout.connect * 1000, timeout.send * 1000, timeout.read * 1000)
    end

    local ok, err = sk:connect(node.host, node.port)
    if not ok then
        core.log.error("failed to connect: ", err)
        return nil
    end

    if up_conf.scheme == "tls" then
        -- TODO: support mTLS
        local ok, err = sk:sslhandshake(nil, node.host)
        if not ok then
            core.log.error("failed to handshake: ", err)
            return nil
        end
    end

    return sk
end


---
-- Disconnect xRPC upstream socket according to the configuration
--
-- @function xrpc.sdk.disconnect_upstream
-- @tparam table upstream xRPC upstream socket
-- @tparam table up_conf upstream configuration
function _M.disconnect_upstream(upstream, up_conf)
    return upstream:close()
end


---
-- Returns the request level ctx with an id
--
-- @function xrpc.sdk.get_req_ctx
-- @tparam table session xrpc session
-- @tparam string id ctx id
-- @treturn table the request level ctx
function _M.get_req_ctx(session, id)
    if not id then
        error("id is required")
    end

    local ctx = session._ctxs[id]
    if ctx then
        return ctx
    end

    local ctx = core.tablepool.fetch("xrpc_ctxs", 4, 4)
    -- fields start with '_' should not be accessed by the protocol implementation
    ctx._id = id
    core.ctx.set_vars_meta(ctx)
    ctx.conf_type = "xrpc-" .. session.route.protocol.name .. "-logger"

    session._ctxs[id] = ctx

    ctx._rpc_start_time = ngx_now()
    return ctx
end


---
-- Returns the new router if the stream routes are changed
--
-- @function xrpc.sdk.get_router
-- @tparam table session xrpc session
-- @tparam string version the current router version, should come from the last call
-- @treturn boolean whether there is a change
-- @treturn table the new router under the specific protocol
-- @treturn string the new router version
function _M.get_router(session, version)
    local protocol_name = session.route.protocol.name
    local id = session.route.id

    local items, conf_version = router.routes()
    if version == conf_version then
        return false
    end

    local proto_router = {}
    for _, item in config_util.iterate_values(items) do
        if item.value == nil then
            goto CONTINUE
        end

        local route = item.value
        if route.protocol.name ~= protocol_name then
            goto CONTINUE
        end

        if tostring(route.protocol.superior_id) ~= id then
            goto CONTINUE
        end

        tab_insert(proto_router, route)

        ::CONTINUE::
    end

    return true, proto_router, conf_version
end


---
-- Set the session's current upstream according to the route's configuration
--
-- @function xrpc.sdk.set_upstream
-- @tparam table session xrpc session
-- @tparam table conf the route configuration
-- @treturn nil|string error message if present
function _M.set_upstream(session, conf)
    local up
    if conf.upstream then
        up = conf.upstream
    else
        local id = conf.upstream_id
        up = apisix_upstream.get_by_id(id)
        if not up then
            return str_fmt("upstream %s can't be got", id)
        end
    end

    local key = tostring(up)
    core.log.info("set upstream to: ", key, " conf: ", core.json.delay_encode(up, true))

    session._upstream_key = key
    session.upstream_conf = up
    return nil
end


---
-- Returns the protocol specific metrics object
--
-- @function xrpc.sdk.get_metrics
-- @tparam table session xrpc session
-- @tparam string protocol_name protocol name
-- @treturn nil|table the metrics under the specific protocol if available
function _M.get_metrics(session, protocol_name)
    local metric_conf = session.route.protocol.metric
    if not (metric_conf and metric_conf.enable) then
        return nil
    end
    return metrics.load(protocol_name)
end


return _M
