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
local type           = type
local setmetatable   = setmetatable
local ngx            = ngx
local ngx_sleep      = ngx.sleep
local thread_spawn   = ngx.thread.spawn
local thread_kill    = ngx.thread.kill
local worker_exiting = ngx.worker.exiting
local shared_dict    = ngx.shared["mcp-session"] -- TODO: rename to something like mcp-broker
local core           = require("apisix.core")
local broker_utils   = require("apisix.plugins.mcp.broker.utils")

local _M = {}
local mt = { __index = _M }


local STORAGE_SUFFIX_QUEUE   = ":queue"
local STORAGE_SUFFIX_SESSION = ":session"

-- a live SSE session refreshes its marker well within this window, so the
-- marker (and any queue left behind) expires on its own if the session goes
-- away without running its teardown path
local SESSION_TTL = 60
-- upper bound on the number of messages buffered for a single session, so one
-- session cannot by itself consume the whole shared dictionary
local QUEUE_MAX_LENGTH = 1024


function _M.new(opts)
    return setmetatable({
        session_id = opts.session_id,
        event_handler = {}
    }, mt)
end


function _M.on(self, event, cb)
    self.event_handler[event] = cb
end


-- record that this session has a live SSE connection on some worker. the
-- message endpoint consults this before queueing, so that a request can only
-- enqueue work for a session that actually exists. refreshed periodically by
-- the owning session and removed on teardown; the TTL is a backstop for an
-- unclean teardown.
function _M.register(self)
    local ok, err = shared_dict:set(self.session_id .. STORAGE_SUFFIX_SESSION,
                                    true, SESSION_TTL)
    if not ok then
        return nil, "failed to register session: " .. err
    end
    return true
end


function _M.unregister(self)
    shared_dict:delete(self.session_id .. STORAGE_SUFFIX_SESSION)
    shared_dict:delete(self.session_id .. STORAGE_SUFFIX_QUEUE)
end


-- whether a session currently has a live SSE connection. module-level by
-- design: the message endpoint checks this before creating a server.
function _M.session_exists(session_id)
    if not session_id then
        return false
    end
    return shared_dict:get(session_id .. STORAGE_SUFFIX_SESSION) ~= nil
end


function _M.push(self, message)
    if not message then
        return nil, "message is nil"
    end
    local key = self.session_id .. STORAGE_SUFFIX_QUEUE
    local len = shared_dict:llen(key)
    if len and len >= QUEUE_MAX_LENGTH then
        return nil, "queue is full"
    end
    local ok, err = shared_dict:rpush(key, message)
    if not ok then
        return nil, "failed to push message to queue: " .. err
    end
    -- keep the queue from outliving its session if teardown is missed
    shared_dict:expire(key, SESSION_TTL)
    return true
end


function _M.start(self)
    self.thread = thread_spawn(function()
        while not worker_exiting() do
            local item, err = shared_dict:lpop(self.session_id .. STORAGE_SUFFIX_QUEUE)
            if err then
                core.log.info("session ", self.session_id,
                              " exit, failed to pop message from queue: ", err)
                break
            end
            if item and type(item) == "string"
                and type(self.event_handler[broker_utils.EVENT_MESSAGE]) == "function" then
                self.event_handler[broker_utils.EVENT_MESSAGE](
                    core.json.decode(item), { raw = item }
                )
            end

            ngx_sleep(0.1) -- yield to other light threads
        end
    end)
end


function _M.close(self)
    if self.thread then
        thread_kill(self.thread)
        self.thread = nil
    end
end


return _M
