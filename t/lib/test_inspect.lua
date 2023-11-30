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

--
-- Don't edit existing code, because the hooks are identified by line number.
-- Instead, append new code to this file.
--
local _M = {}

function _M.run1()
    local var1 = "hello"
    local var2 = "world"
    return var1 .. var2
end

local upvar1 = 2
local upvar2 = "yes"
function _M.run2()
    return upvar1
end

function _M.run3()
    return upvar1 .. upvar2
end

local str = string.rep("a", 8192) .. "llzz"

local sk = require("socket")

function _M.hot1()
    local t1 = sk.gettime()
    for i=1,100000 do
        string.find(str, "ll", 1, true)
    end
    local t2 = sk.gettime()
    return t2 - t1
end

function _M.hot2()
    local t1 = sk.gettime()
    for i=1,100000 do
        string.find(str, "ll", 1, true)
    end
    local t2 = sk.gettime()
    return t2 - t1
end

return _M
