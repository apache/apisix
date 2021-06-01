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
local ffi = require("ffi")
local ffi_str = ffi.string
local ffi_errno = ffi.errno
local C = ffi.C
local tostring = tostring
local type = type


local _M = {}


ffi.cdef[[
    int setenv(const char *name, const char *value, int overwrite);
    char *strerror(int errnum);
]]


local function err()
    return ffi_str(C.strerror(ffi_errno()))
end


-- setenv sets the value of the environment variable
function _M.setenv(name, value)
    local tv = type(value)
    if type(name) ~= "string" or (tv ~= "string" and tv ~= "number") then
        return false, "invalid argument"
    end

    value = tostring(value)
    local ok = C.setenv(name, value, 1) == 0
    if not ok then
        return false, err()
    end
    return true
end


return _M
