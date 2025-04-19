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
local type         = type
local rawget       = rawget
local rawset       = rawset
local setmetatable = setmetatable
local ngx          = ngx
local shared_dict  = ngx.shared["mcp-session"]
local core         = require("apisix.core")

local SESSION_LAST_ACTIVE_AT        = "_last_active_at"
local SESSION_THRESHOLD_PING        = 30000  --TODO allow customize
local SESSION_THRESHOLD_TIMEOUT     = 60000  --TODO allow customize
local STORAGE_SUFFIX_LAST_ACTIVE_AT = ":last_active_at"
local STORAGE_SUFFIX_PING_ID        = ":ping_id"
local STORAGE_SUFFIX_QUEUE          = ":queue"

local _M = {}
local mt = {
    __index = function (table, key)
        if key == SESSION_LAST_ACTIVE_AT then
            return shared_dict:get(table.id .. STORAGE_SUFFIX_LAST_ACTIVE_AT) or 0
        end
        return rawget(table, key) or _M[key]
    end,
    __newindex = function (table, key, value)
        if key == SESSION_LAST_ACTIVE_AT then
            shared_dict:set(table.id .. STORAGE_SUFFIX_LAST_ACTIVE_AT, value)
        else
            rawset(table, key, value)
        end
    end
}

local function gen_session_id()
    return core.id.gen_uuid_v4()
end


function _M.new()
    local session = setmetatable({
        id = gen_session_id(),
    }, mt)
    shared_dict:set(session.id, core.json.encode(session))
    shared_dict:set(session.id .. STORAGE_SUFFIX_LAST_ACTIVE_AT, ngx.time())
    shared_dict:set(session.id .. STORAGE_SUFFIX_PING_ID, 0)
    return session
end

-- for state machine
function _M.session_initialize(self, params)
    self.protocol_version = params.protocolVersion
    self.client_info = params.clientInfo
    self.capabilities = params.capabilities
    self.state = _M.STATE_INITIALIZED
end


function _M.session_need_ping(self)
    return self[SESSION_LAST_ACTIVE_AT] + SESSION_THRESHOLD_PING / 1000 <= ngx.time()
end


function _M.session_timed_out(self)
    return self[SESSION_LAST_ACTIVE_AT] + SESSION_THRESHOLD_TIMEOUT / 1000 <= ngx.time()
end


function _M.session_next_ping_id(self)
    return shared_dict:incr(self.id .. STORAGE_SUFFIX_PING_ID, 1)
end


function _M.on_session_pong(self)
    self[SESSION_LAST_ACTIVE_AT] = ngx.time()
end


function _M.push_message_queue(self, task)
    return shared_dict:rpush(self.id .. STORAGE_SUFFIX_QUEUE, task)
end


function _M.pop_message_queue(self)
    return shared_dict:lpop(self.id .. STORAGE_SUFFIX_QUEUE)
end


function _M.destroy(self)
    shared_dict:delete(self.id)
    shared_dict:delete(self.id .. STORAGE_SUFFIX_LAST_ACTIVE_AT)
    shared_dict:delete(self.id .. STORAGE_SUFFIX_PING_ID)
    shared_dict:delete(self.id .. STORAGE_SUFFIX_QUEUE)
end


function _M.recover(session_id)
    local session, err = shared_dict:get(session_id)
    if not session then
        return nil, err
    end
    if type(session) ~= "string" then
        return nil, "session data is invalid"
    end
    return setmetatable(core.json.decode(session), mt)
end

return _M
