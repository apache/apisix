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
local ngx_now = ngx.now
local OK = ngx.OK
local DECLINED = ngx.DECLINED
local DONE = ngx.DONE


local _M = {}


local function open_session(conn_ctx)
    conn_ctx.xrpc_session = {
        upstream_conf = conn_ctx.matched_upstream,
        id_seq = 0,
    }
    return conn_ctx.xrpc_session
end


local function close_session(session, upstream_broken)
    local upstream = session.upstream
    if upstream then
        if upstream_broken then
            upstream:close()
        else
            upstream:setkeepalive()
        end
    end
end


local function put_req_ctx(session, ctx)
    local id = ctx.id
    session.ctxs[id] = nil

    core.tablepool.release("xrpc_ctxs", ctx)
end


local function finish_req(protocol, session, ctx)
    ctx.rpc_end_time = ngx_now()

    protocol.log(session, ctx)
    put_req_ctx(session, ctx)
end


local function open_upstream(protocol, session, ctx)
    if session.upstream then
        return OK, session.upstream
    end

    local state, upstream = protocol.connect_upstream(session, session)
    if state ~= OK then
        return state, nil
    end

    session.upstream = upstream
    return OK, upstream
end


function _M.run(protocol, conn_ctx)
    local session = open_session(conn_ctx)
    local downstream = protocol.init_downstream(session)
    local upstream_broken = false

    while true do
        local status, ctx = protocol.from_downstream(session, downstream)
        if status ~= OK then
            if ctx ~= nil then
                finish_req(session, ctx)
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
        local status, upstream = open_upstream(protocol, session, ctx)
        if status ~= OK then
            break
        end

        status = protocol.to_upstream(session, ctx, downstream, upstream)
        if status == DECLINED then
            upstream_broken = true
            break
        end

        if status == DONE then
            -- for Unary request we can directly reply here
            goto continue
        end

        ::continue::
    end

    close_session(session, upstream_broken)

    -- return non-zero code to terminal the session
    return 200
end


return _M
