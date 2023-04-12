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
local core = require("apisix.core")

limit_count.handle_incoming = function (self, key, cost, commit)
  local dict = self.dict
  local limit = self.limit
  local window = self.window

  local remaining, err

  if commit then
      remaining, err = dict:incr(key, 0 - cost, limit, window)
      if not remaining then
          return nil, err
      end
  else
      remaining = (dict:get(key) or limit) - cost
  end

  if remaining < 0 then
      return nil, "rejected"
  end

  return 0, remaining
end

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
        limit_count = limit_count.new(plugin_name, limit, window),
        dict = ngx.shared[plugin_name .. "-reset-header"]
    }

    return setmetatable(self, mt)
end

function _M.incoming(self, key, cost, commit, conf)
    local delay, remaining = self.limit_count:handle_incoming(key, cost, commit)
    local reset = 0
    if not delay then
        return delay, remaining, reset
    end

    if remaining == conf.count - cost then
        reset = set_endtime(self, key, conf.time_window)
    else
        reset = read_reset(self, key)
    end

    return delay, remaining, reset
end

return _M
