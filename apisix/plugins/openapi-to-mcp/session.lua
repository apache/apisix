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
local core       = require("apisix.core")
local ngx_shared = ngx.shared
local type       = type
local tostring   = tostring

local _M = {}

local DICT_NAME = "mcp-session"

-- An idle session is dropped after 30 minutes.
local SESSION_TTL = 1800

-- mcp-bridge stores its own sessions in this dict with a ":queue" suffix, so
-- these keys carry a prefix of their own rather than relying on two plugins
-- never generating the same id.
local KEY_PREFIX = "openapi-to-mcp:"
local ALIVE_SUFFIX = ":alive"
local QUEUE_SUFFIX = ":queue"


local function alive_key(session_id)
    return KEY_PREFIX .. session_id .. ALIVE_SUFFIX
end


local function queue_key(session_id)
    return KEY_PREFIX .. session_id .. QUEUE_SUFFIX
end


local function store()
    local dict = ngx_shared[DICT_NAME]
    if not dict then
        return nil, "shared dict '" .. DICT_NAME .. "' is not declared"
    end
    return dict
end



-- The value stored under the :alive key carries two things.
--
-- `owner` identifies the route, and the consumer if one was authenticated, the
-- stream belongs to. A message is only accepted from the same owner: without it
-- a session id issued on one route could be used to push a result into that
-- stream from another route, with another route's configuration.
--
-- `context` is what the stream resolved when it was opened -- the base_url and
-- the headers, after variable substitution. It is stored with the session
-- because a message POST carries none of the request state those variables were
-- read from: the endpoint the client is handed is "<path>?sessionId=<uuid>" and
-- nothing else. Resolving again there would silently produce empty values. A
-- configuration that holds no variables freezes nothing.
function _M.create(owner, context)
    local dict, err = store()
    if not dict then
        return nil, err
    end

    local marker, encode_err = core.json.encode({
        owner = owner or "",
        context = type(context) == "table" and context or nil,
    })
    if not marker then
        core.log.warn("failed to store MCP session context: ", encode_err)
        marker = core.json.encode({ owner = owner or "" })
    end

    local session_id = core.id.gen_uuid_v4()
    local ok, set_err = dict:set(alive_key(session_id), marker, SESSION_TTL)
    if not ok then
        return nil, "failed to register session: " .. tostring(set_err)
    end
    return session_id
end


-- What was stored with the session, or nil when there is nothing to read or it
-- cannot be understood -- in which case the session counts as gone.
local function stored_marker(session_id)
    if type(session_id) ~= "string" or session_id == "" then
        return nil
    end
    local dict = store()
    if not dict then
        return nil
    end
    local stored = dict:get(alive_key(session_id))
    if type(stored) ~= "string" then
        return nil
    end
    local decoded = core.json.decode(stored)
    if type(decoded) ~= "table" then
        return nil
    end
    return decoded
end


-- The values frozen by _M.create(), or nil for a session that stored none.
function _M.context(session_id)
    local marker = stored_marker(session_id)
    return marker and marker.context or nil
end


function _M.exists(session_id, owner)
    local marker = stored_marker(session_id)
    if not marker then
        return false
    end
    return marker.owner == (owner or "")
end


-- Keeps the liveness marker from expiring while the stream is still open.
-- Returns false when the marker could not be refreshed, which means the stream
-- is about to become unreachable for its own message endpoint.
function _M.touch(session_id)
    local dict, err = store()
    if not dict then
        return false, err
    end
    -- Re-set the value that is already there: it carries the owner and the
    -- frozen context, and writing a placeholder back would drop both halfway
    -- through the session.
    local key = alive_key(session_id)
    local marker = dict:get(key)
    if marker == nil then
        return false, "session is gone"
    end
    local ok, set_err = dict:set(key, marker, SESSION_TTL)
    if not ok then
        return false, "failed to refresh session: " .. tostring(set_err)
    end
    return true
end


-- The POST that carries a JSON-RPC message and the GET that streams the answer
-- may land on different workers, so the queue lives in shared memory.
function _M.push(session_id, message)
    local dict, err = store()
    if not dict then
        return nil, err
    end
    -- Never resurrect the queue of a torn-down session: nothing would drain it,
    -- and a shared dict list carries no TTL, so the entry would sit there until
    -- the dict runs out of room.
    if dict:get(alive_key(session_id)) == nil then
        return nil, "session is gone"
    end

    local length, push_err = dict:rpush(queue_key(session_id), message)
    if not length then
        return nil, "failed to queue message: " .. tostring(push_err)
    end

    -- The stream that drains this queue usually runs in another worker, so it
    -- can tear the session down between the check above and the push. There is
    -- no compare-and-set on a shared dict, but checking again afterwards is
    -- enough: either destroy ran before the push and this sees the session
    -- gone, or it ran after and deleted the queue itself. Neither order leaves
    -- a list behind.
    if dict:get(alive_key(session_id)) == nil then
        dict:delete(queue_key(session_id))
        return nil, "session is gone"
    end

    return true
end


function _M.pop(session_id)
    local dict = store()
    if not dict then
        return nil
    end
    local message = dict:lpop(queue_key(session_id))
    return message
end


function _M.destroy(session_id)
    local dict = store()
    if not dict then
        return
    end
    -- shared dict lists carry no TTL of their own, so drop it explicitly
    dict:delete(queue_key(session_id))
    dict:delete(alive_key(session_id))
end


return _M
