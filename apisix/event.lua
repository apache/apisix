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

local _M = {}

_M.EVENTS_MODULE_LUA_RESTY_WORKER_EVENTS = 'lua-resty-worker-events'
_M.EVENTS_MODULE_LUA_RESTY_EVENTS = 'lua-resty-events'


-- use lua-resty-worker-events
local function init_worker_events()
    local we = require("resty.worker.events")
    local shm = ngx.config.subsystem == "http" and "worker-events" or "worker-events-stream"
    local ok, err = we.configure({shm = shm, interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end

    return we
end


function _M.init_worker()
    -- use lua-resty-worker-events default now
    _M.worker_events = init_worker_events()
end


function _M.register(self, ...)
    return self.worker_events.register(...)
end


function _M.event_list(self, ...)
    return self.worker_events.event_list(...)
end


function _M.post(self, ...)
    return self.worker_events.post(...)
end


return _M
