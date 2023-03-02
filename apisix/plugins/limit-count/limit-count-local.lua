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
local limit_local_new = require("resty.limit.count").new
local ngx = ngx
local ngx_time = ngx.time
local assert = assert
local setmetatable = setmetatable
local core = require("apisix.core")

local _M = {}

local mt = {
    __index = _M
}

local function set_endtime(self, key, time_window)
    -- set an end time
    local end_time = ngx_time() + time_window
    -- save to dict by key
    local success, err = self.dict:set(key, end_time, time_window)

    if not success then
        core.log.error("dict set key ", key, " error: ", err)
    end

    local reset = time_window
    return reset
end

local function read_reset(self, key)
    -- read from dict
    local end_time = (self.dict:get(key) or 0)
    local reset = end_time - ngx_time()
    if reset < 0 then
        reset = 0
    end
    return reset
end

function _M.new(plugin_name, limit, window)
    assert(limit > 0 and window > 0)

    local self = {
        limit_count = limit_local_new(plugin_name, limit, window),
        dict = ngx.shared["plugin-limit-count-reset-header"]
    }

    return setmetatable(self, mt)
end

function _M.incoming(self, key, commit, conf)
    local delay, remaining = self.limit_count:incoming(key, commit)
    local reset = 0
    if not delay then
        return delay, remaining, reset
    end

    if remaining == conf.count - 1 then
        reset = set_endtime(self, key, conf.time_window)
    else
        reset = read_reset(self, key)
    end

    return delay, remaining, reset
end

return _M
