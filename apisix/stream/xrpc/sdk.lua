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
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local ngx_now = ngx.now
local tab_insert = table.insert
local error = error
local tostring = tostring


local _M = {}


---
-- Returns the connected xRPC upstream socket according to the configuration
--
-- @function xrpc.sdk.connect_upstream
-- @tparam table selected upstream node
-- @tparam table upstream configuration
-- @treturn table|nil the xRPC upstream socket, or nil if failed
function _M.connect_upstream(node, up_conf)
    local sk = xrpc_socket.upstream.socket()

    local ok, err = sk:connect(node.host, node.port)
    if not ok then
        core.log.error("failed to connect: ", err)
        return nil
    end
    -- TODO: support timeout

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
-- Returns disconnected xRPC upstream socket according to the configuration
--
-- @function xrpc.sdk.disconnect_upstream
-- @tparam table xRPC upstream socket
-- @tparam table upstream configuration
-- @tparam boolean is the upstream already broken
function _M.disconnect_upstream(upstream, up_conf, upstream_broken)
    if upstream_broken then
        upstream:close()
    else
        -- TODO: support keepalive according to the up_conf
        upstream:setkeepalive()
    end
end


---
-- Returns the request level ctx with an id
--
-- @function xrpc.sdk.get_req_ctx
-- @tparam table xrpc session
-- @tparam string optional ctx id
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
    session._ctxs[id] = ctx

    ctx._rpc_start_time = ngx_now()
    return ctx
end


---
-- Returns the new router if the stream routes are changed
--
-- @function xrpc.sdk.get_router
-- @tparam table xrpc session
-- @tparam string the current router version, should come from the last call
-- @treturn boolean whether there is a change
-- @treturn table the new router under the specific protocol
-- @treturn string the new router version
function _M.get_router(session, version)
    local protocol_name = session._route.protocol.name
    local id = session._route.id

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
-- @tparam table xrpc session
-- @tparam table the route configuration
function _M.set_upstream(session, conf)
    local up
    if conf.upstream then
        up = conf.upstream
        -- TODO: support upstream_id
    end

    local key = tostring(conf)
    core.log.info("set upstream to: ", key)

    session._upstream_key = key
    session.upstream_conf = up
end


return _M
