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

local assert            = assert
local math              = require "math"
local floor             = math.floor
local _M = {version = 0.3}


function _M.incoming(self, red, key, commit)
    local max = self.max
    self.committed = false
    key = "limit_conn" .. ":" .. key

    local conn, err
    if commit then
        conn, err = red:incrby(key, 1)
        if not conn then
            return nil, err
        end

        if conn > max + self.burst then
            conn, err = red:incrby(key, -1)
            if not conn then
                return nil, err
            end
            return nil, "rejected"
        end
        self.committed = true

    else
        local conn_from_red, err = red:get(key)
        if err then
            return nil, err
        end
        conn = (conn_from_red or 0) + 1
    end

    if conn > max then
        -- make the excessive connections wait
        return self.unit_delay * floor((conn - 1) / max), conn
    end

    -- we return a 0 delay by default
    return 0, conn
end


function _M.leaving(self, red, key, req_latency)
    assert(key)
    key = "limit_conn" .. ":" .. key

    local conn, err = red:incrby(key, -1)
    if not conn then
        return nil, err
    end

    if req_latency then
        local unit_delay = self.unit_delay
        self.unit_delay = (req_latency + unit_delay) / 2
    end

    return conn
end


return _M
