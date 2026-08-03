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
local limit_count = require("resty.limit.count")
local sliding_window = require("apisix.plugins.limit-count.sliding-window.sliding-window")
local shared_dict_store = require("apisix.plugins.limit-count.sliding-window."
                                  .. "store.shared-dict")

local ngx = ngx
local type = type
local ngx_now = ngx.now
local assert = assert
local setmetatable = setmetatable
local core = require("apisix.core")

local _M = {}

local mt = {
    __index = _M
}

local function set_endtime(self, key, time_window)
    -- set an end time
    local end_time = ngx_now() + time_window
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
    local reset = end_time - ngx_now()
    if reset < 0 then
        reset = 0
    end
    return reset
end

function _M.new(plugin_name, limit, window, window_type)
    assert(limit > 0 and window > 0)

    if window_type == "sliding" then
        local shd_store, err = shared_dict_store.new({name = plugin_name})
        if not shd_store then
            return nil, err
        end

        local sw_limit_count
        sw_limit_count, err = sliding_window.new(shd_store, limit, window)

        if not sw_limit_count then
            return nil, err
        end

        local self = {
            limit = limit,
            window = window,
            window_type = window_type,
            limit_count = sw_limit_count,
        }

        return setmetatable(self, mt)
    end

    local self = {
        limit = limit,
        window = window,
        window_type = window_type,
        limit_count = limit_count.new(plugin_name, limit, window),
        dict = ngx.shared[plugin_name .. "-reset-header"]
    }

    return setmetatable(self, mt)
end

function _M.incoming(self, key, flag_or_cost, _conf, cost_arg)
    local cost
    if type(flag_or_cost) == "boolean" then
        -- old API: incoming(key, flag, conf, cost)
        cost = cost_arg
    else
        -- new API: incoming(key, cost)
        cost = flag_or_cost
    end

    if self.window_type == "sliding" then
        return self.limit_count:incoming(key, cost)
    end

    local delay, consumed_or_err = self.limit_count:incoming(key, true, cost)
    local reset

    local remaining_or_err = consumed_or_err
    if type(consumed_or_err) == "number" then
        remaining_or_err = self.limit - consumed_or_err
    end

    if remaining_or_err == self.limit - cost then
        reset = set_endtime(self, key, self.window)
    else
        reset = read_reset(self, key)
    end

    return delay, remaining_or_err, reset
end

return _M
