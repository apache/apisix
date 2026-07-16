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
local tostring = tostring
local string_format = string.format
local math_floor = math.floor
local math_ceil = math.ceil

local ngx_now = ngx.now
local setmetatable = setmetatable
local log = require("apisix.core.log")

local _M = {}
local mt = { __index = _M }

local function round_off_decimal_places(input, places)
    local multiplier = 10 ^ places
    return math_ceil(input * multiplier) / multiplier
end


-- uniquely identifies the window associated with given time
local function get_window_id(self, time)
    return tostring(math_floor(time / self.window_size))
end


local function get_counter_key(self, key, time)
    local wid = get_window_id(self, time)
    -- plugin_name (Redis stores only) keeps plugins that share a key apart,
    -- like the fixed-window Redis path already does.
    if self.plugin_name then
        return string_format("%s:%s.%s.counter", self.plugin_name, key, wid)
    end
    return string_format("%s.%s.counter", key, wid)
end


function _M.new(store, limit, window_size, red_cli)
    if not store then
        return nil, "'store' parameter is missing"
    end
    if not store.incr then
        return nil, "'store' has to implement 'incr' function"
    end
    if not store.get then
        return nil, "'store' has to implement 'get' function"
    end
    if not store.check_and_incr then
        return nil, "'store' has to implement 'check_and_incr' function"
    end

    return setmetatable({
        store = store,
        limit = limit,
        window_size = window_size,
        red_cli = red_cli
    }, mt)
end


function _M.new_with_red_cli_factory(store, limit, window_size, red_cli_factory, conf)
    if not store then
        return nil, "'store' parameter is missing"
    end
    if not store.incr then
        return nil, "'store' has to implement 'incr' function"
    end
    if not store.get then
        return nil, "'store' has to implement 'get' function"
    end
    if not store.check_and_incr then
        return nil, "'store' has to implement 'check_and_incr' function"
    end

    return setmetatable({
        store = store,
        limit = limit,
        window_size = window_size,
        conf = conf,
        red_cli_factory = red_cli_factory
    }, mt)
end


local function get_desired_delay(self, remaining_time, last_rate, count)
    if last_rate == 0 then
        return remaining_time
    end

    local desired_delay = remaining_time - (self.limit - count) / last_rate

    if desired_delay <= 0 then
        return 0
    end

    return desired_delay
end


function _M.incoming(self, key, cost)
    local now = ngx_now()
    local counter_key = get_counter_key(self, key, now)
    local last_counter_key = get_counter_key(self, key, now - self.window_size)
    local remaining_time = self.window_size - now % self.window_size

    local red_cli, err
    if not self.red_cli and self.red_cli_factory then
        red_cli, err = self.red_cli_factory(self.conf)
        if not red_cli then
            return nil, err, 0
        end
    end

    -- One atomic step decides accept/reject and increments only on accept, so
    -- concurrent requests can't all pass the check before any increment lands.
    local expiry = self.window_size * 2
    local res
    res, err = self.store:check_and_incr(counter_key, last_counter_key, cost,
                    self.limit, self.window_size, remaining_time, expiry,
                    self.red_cli or red_cli)

    if red_cli then
        red_cli:set_keepalive(10000, 100)
    end

    if not res then
        return nil, err, 0
    end

    local accepted, count, last_count = res[1], res[2], res[3]
    local last_rate = last_count / self.window_size
    local estimated_last_window_count = last_rate * remaining_time
    log.debug("accepted: ", accepted, ", count: ", count, ", limit: ", self.limit)

    if accepted == 0 then
        if count >= self.limit then
            return nil, "rejected", round_off_decimal_places(remaining_time, 2)
        end
        local desired_delay = get_desired_delay(self, remaining_time, last_rate, count)
        return nil, "rejected", round_off_decimal_places(desired_delay, 2)
    end

    local remaining = self.limit - count - estimated_last_window_count
    return 0, math_floor(remaining), round_off_decimal_places(remaining_time, 2)
end


-- commit unconditionally adds an already-permitted delta to the counter and
-- reports the resulting remaining, skipping the pre-increment rejection that
-- incoming() applies. Delayed sync flushes a locally-permitted delta with it:
-- those requests already happened, so the delta must reach the shared store
-- even when the window is already at/over the limit -- otherwise the global
-- count permanently under-records. This mirrors the fixed-window backend, whose
-- Redis script likewise always increments before it can report "rejected".
function _M.commit(self, key, cost)
    local now = ngx_now()
    local counter_key = get_counter_key(self, key, now)
    local remaining_time = self.window_size - now % self.window_size

    local red_cli, err
    if not self.red_cli and self.red_cli_factory then
        red_cli, err = self.red_cli_factory(self.conf)
        if not red_cli then
            return nil, err, 0
        end
    end

    local expiry = self.window_size * 2
    local new_count
    new_count, err = self.store:incr(counter_key, cost, expiry, self.red_cli or red_cli)
    if err then
        return nil, err, 0
    end

    if red_cli then
        red_cli:set_keepalive(10000, 100)
    end

    local remaining = math_floor(self.limit - new_count)
    return 0, remaining, round_off_decimal_places(remaining_time, 2)
end

return _M
