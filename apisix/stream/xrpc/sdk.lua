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
local xrpc_socket = require("resty.apisix.stream.xrpc.socket")
local ngx_now = ngx.now


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

    if up_conf.scheme == "tls" then
        local ok, err = sk:sslhandshake(nil, node.host)
        if not ok then
            core.log.error("failed to handshake: ", err)
            return nil
        end
    end

    return sk
end


---
-- Returns the request level ctx with an optional id
--
-- @function xrpc.sdk.get_req_ctx
-- @tparam table xrpc session
-- @tparam string optional ctx id
-- @treturn table the request level ctx
function _M.get_req_ctx(session, id)
    if not id then
        id = session.id_seq
        session.id_seq = session.id_seq + 1
    end

    local ctx = core.tablepool.fetch("xrpc_ctxs")
    session.ctxs[id] = ctx

    ctx.rpc_start_time = ngx_now()
    return ctx
end


return _M
