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

--- Common library about math
--
-- @module core.math
local _M = {}


---
-- Calculate the greatest common divisor (GCD) of two numbers
--
-- @function core.math.gcd
-- @tparam number a
-- @tparam number b
-- @treturn number the GCD of a and b
local function gcd(a, b)
    if b == 0 then
        return a
    end

    return gcd(b, a % b)
end
_M.gcd = gcd


return _M
