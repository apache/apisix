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


local STORAGE_SUFFIX_QUEUE = ":queue"
local STORAGE_SUFFIX_ALIVE = ":alive"

-- liveness marker TTL in seconds. it is refreshed on each keepalive so it
-- comfortably outlives the 30s ping interval, and self-expires if the worker
-- holding the session goes away without running teardown.
local ALIVE_TTL = 90


function _M.new(opts)
    return setmetatable({
        session_id = opts.session_id,
        event_handler = {}
    }, mt)
end


function _M.on(self, event, cb)
    self.event_handler[event] = cb
end


function _M.push(self, message)
    if not message then
        return nil, "message is nil"
    end
    local ok, err = shared_dict:rpush(self.session_id .. STORAGE_SUFFIX_QUEUE, message)
    if not ok then
        return nil, "failed to push message to queue: " .. err
    end
    return true
end


function _M.mark_alive(self)
    return shared_dict:set(self.session_id .. STORAGE_SUFFIX_ALIVE, true, ALIVE_TTL)
end


function _M.clear_alive(self)
    shared_dict:delete(self.session_id .. STORAGE_SUFFIX_ALIVE)
end


-- whether an SSE session with this id is currently established on any worker.
-- called as a plain function (no instance) from the message endpoint.
function _M.is_alive(session_id)
    if not session_id then
        return false
    end
    return shared_dict:get(session_id .. STORAGE_SUFFIX_ALIVE) ~= nil
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
