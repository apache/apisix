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

local require      = require
local error        = error
local assert       = assert
local tostring     = tostring
local pairs        = pairs
local setmetatable = setmetatable
local ngx          = ngx
local core         = require("apisix.core")

local _M = {
    events_module = nil,
}

_M.EVENTS_MODULE_LUA_RESTY_WORKER_EVENTS = 'lua-resty-worker-events'
_M.EVENTS_MODULE_LUA_RESTY_EVENTS = 'lua-resty-events'


-- use lua-resty-worker-events
local function init_resty_worker_events()
    _M.events_module = _M.EVENTS_MODULE_LUA_RESTY_WORKER_EVENTS

    local we = require("resty.worker.events")
    local shm = ngx.config.subsystem == "http" and "worker-events" or "worker-events-stream"
    local ok, err = we.configure({shm = shm, interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end

    return we
end


-- use lua-resty-events
local function init_resty_events()
    _M.events_module = _M.EVENTS_MODULE_LUA_RESTY_EVENTS

    local listening = "unix:" .. ngx.config.prefix() .. "logs/"
    if ngx.config.subsystem == "http" then
        listening = listening .. "worker_events.sock"
    else
        listening = listening .. "stream_worker_events.sock"
    end
    core.log.info("subsystem: " .. ngx.config.subsystem .. " listening sock: " .. listening)

    local opts = {
        unique_timeout = 5,     -- life time of unique event data in lrucache
        broker_id = 0,          -- broker server runs in nginx worker #0
        listening = listening,  -- unix socket for broker listening
    }

    local we = require("resty.events.compat")
    assert(we.configure(opts))
    assert(we.configured())

    return we
end


function _M.init_worker()
    if _M.inited then
        -- prevent duplicate initializations in the same worker to
        -- avoid potentially unexpected behavior
        return
    end

    _M.inited = true

    local conf = core.config.local_conf()
    local module_name = core.table.try_read_attr(conf, "apisix", "events", "module")
                            or _M.EVENTS_MODULE_LUA_RESTY_WORKER_EVENTS

    if module_name == _M.EVENTS_MODULE_LUA_RESTY_EVENTS then
        -- use lua-resty-events as an event module via the apisix.events.module
        -- key in the configuration file
        _M.worker_events = init_resty_events()
    else
        -- use lua-resty-worker-events default now
        _M.worker_events = init_resty_worker_events()
    end
end


function _M.register(self, ...)
    return self.worker_events.register(...)
end


function _M.event_list(self, source, ...)
    -- a patch for the lua-resty-events to support event_list
    -- this snippet is copied from the lua-resty-worker-events lib
    if self.events_module == _M.EVENTS_MODULE_LUA_RESTY_EVENTS then
        local events = { _source = source }
        for _, event in pairs({...}) do
            events[event] = event
        end
        return setmetatable(events, {
            __index = function(_, key)
            error("event '"..tostring(key).."' is an unknown event", 2)
            end
        })
    end

    -- the lua-resty-worker-events has a built-in event_list implementation
    return self.worker_events.event_list(source, ...)
end


function _M.post(self, ...)
    return self.worker_events.post(...)
end


function _M.get_healthcheck_events_modele(self)
    if self.events_module == _M.EVENTS_MODULE_LUA_RESTY_EVENTS then
        return "resty.events"
    else
        return "resty.worker.events"
    end
end


return _M
