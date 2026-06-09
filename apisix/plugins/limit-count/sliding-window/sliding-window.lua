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
    return string_format("%s.%s.counter", key, wid)
end


local function get_last_rate(self, sample, now_ms, red_cli)
    local a_window_ago_from_now = now_ms - self.window_size
    local last_counter_key = get_counter_key(self, sample, a_window_ago_from_now)

    local last_count, err = self.store:get(last_counter_key, red_cli)
    if err then
        return nil, err
    end
    if not last_count then
        last_count = 0
    end
    if last_count > self.limit then
        -- in incoming we also reactively check for exceeding limit
        -- after icnrementing the counter. So even though counter can be higher
        -- than the limit as a result of racy behaviour we would still throttle
        -- anyway. That is way it is important to correct the last count here
        -- to avoid over-punishment.
        last_count = self.limit
    end

    return last_count / self.window_size
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
    local remaining_time = self.window_size - now % self.window_size

    local red_cli, err
    if not self.red_cli and self.red_cli_factory then
        red_cli, err = self.red_cli_factory(self.conf)
        if not red_cli then
            return nil, err, 0
        end
    end

    local count, err = self.store:get(counter_key, self.red_cli or red_cli)
    if err then
        return nil, err
    end
    if not count then
        count = 0
    end
    log.debug("count: ", count, ", limit: ", self.limit)
    if count >= self.limit then
        return nil, "rejected", round_off_decimal_places(remaining_time, 2)
    end

    local last_rate
    last_rate, err = get_last_rate(self, key, now, self.red_cli or red_cli)
    if err then
      return nil, err, 0
    end

    local estimated_last_window_count = last_rate * remaining_time
    local estimated_final_count = estimated_last_window_count + count
    log.debug("estimated_final_count: ", estimated_final_count, ", limit: ", self.limit)
    if estimated_final_count >= self.limit then
        local desired_delay =
            get_desired_delay(self, remaining_time, last_rate, count)
            return nil, "rejected", round_off_decimal_places(desired_delay, 2)
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

    -- The below limit checking is only to cope with a racy behaviour where
    -- counter for the given sample is incremented at the same time by multiple
    -- sliding_window instances. That is we re-adjust the new count by ignoring
    -- the current occurrence of the sample. Otherwise the limit would
    -- unncessarily be exceeding.
    local new_adjusted_count = new_count - cost
    log.debug("new_adjusted_count: ", new_adjusted_count, ", limit: ", self.limit)

    if new_adjusted_count >= self.limit then
        -- incr above might take long enough to make difference, so
        -- we recalculate time-dependant variables.
        remaining_time = self.window_size - ngx_now() % self.window_size
        return nil, "rejected", round_off_decimal_places(remaining_time, 2)
    end

    local remaining = self.limit - new_count - estimated_last_window_count
    local rounded_remaining = math_floor(remaining)

    return 0, rounded_remaining, round_off_decimal_places(remaining_time, 2)
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
