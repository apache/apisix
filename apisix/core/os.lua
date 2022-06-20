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

--- OS module.
--
-- @module core.os

local ffi = require("ffi")
local ffi_str = ffi.string
local ffi_errno = ffi.errno
local C = ffi.C
local ceil = math.ceil
local floor = math.floor
local error = error
local tostring = tostring
local type = type


local _M = {}
local WNOHANG = 1


ffi.cdef[[
    typedef int32_t pid_t;
    typedef unsigned int  useconds_t;

    int setenv(const char *name, const char *value, int overwrite);
    char *strerror(int errnum);

    int usleep(useconds_t usec);
    pid_t waitpid(pid_t pid, int *wstatus, int options);
]]


local function err()
    return ffi_str(C.strerror(ffi_errno()))
end

---
--  Sets the value of the environment variable.
--
-- @function core.os.setenv
-- @tparam string name The name of environment variable.
-- @tparam string value The value of environment variable.
-- @treturn boolean Results of setting environment variables, true on success.
-- @usage
-- local ok, err = core.os.setenv("foo", "bar")
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


---
--  sleep blockingly in microseconds
--
-- @function core.os.usleep
-- @tparam number us The number of microseconds.
local function usleep(us)
    if ceil(us) ~= floor(us) then
        error("bad microseconds: " .. us)
    end
    C.usleep(us)
end
_M.usleep = usleep


local function waitpid_nohang(pid)
    local res = C.waitpid(pid, nil, WNOHANG)
    if res == -1 then
        return nil, err()
    end
    return res > 0
end


function _M.waitpid(pid, timeout)
    local count = 0
    local step = 1000 * 10
    local total = timeout * 1000 * 1000
    while step * count < total do
        count = count + 1
        usleep(step)
        local ok, err = waitpid_nohang(pid)
        if err then
            return nil, err
        end
        if ok then
            return true
        end
    end
end


return _M
