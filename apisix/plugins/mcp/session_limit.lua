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

local type = type

-- Tracks the number of live MCP SSE sessions handled by the current worker so
-- that a single route cannot spawn an unbounded number of backend processes.
local _M = {}


local count = 0


-- Try to reserve a slot for a new session. Returns true if the worker is below
-- the configured ceiling, false otherwise. Every successful acquire() must be
-- balanced by exactly one release(). A missing or non-numeric ceiling is treated
-- as "no slot available" rather than raising, so a misconfigured or future call
-- site fails closed instead of erroring.
function _M.acquire(max)
    if type(max) ~= "number" or count >= max then
        return false
    end
    count = count + 1
    return true
end


function _M.release()
    if count > 0 then
        count = count - 1
    end
end


function _M.count()
    return count
end


return _M
