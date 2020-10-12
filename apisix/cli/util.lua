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

local pcall = pcall
local popen = io.popen
local stderr = io.stderr
local exit = os.exit
local open = io.open
local tonumber = tonumber
local require = require
local str_format = string.format

local _M = {}


function _M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end


function _M.split(self, sep)
    local sep, fields = sep or ":", {}
    local pattern = str_format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end


-- Note: The `execute_cmd` return value will have a line break at the end,
-- it is recommended to use the `trim` function to handle the return value.
function _M.execute_cmd(cmd)
    local t, err = popen(cmd)
    if not t then
        return nil, "failed to execute command: " .. cmd .. ", error info:" .. err
    end

    local data = t:read("*all")
    t:close()

    return data
end


function _M.die(...)
    stderr:write(...)
    exit(1)
end


function _M.is_32bit_arch()
    local ok, ffi = pcall(require, "ffi")
    if ok then
        -- LuaJIT
        return ffi.abi("32bit")
    end
    local ret = _M.execute_cmd("getconf LONG_BIT")
    local bits = tonumber(ret)
    return bits <= 32
end


function _M.local_dns_resolver(file_path)
    local file, err = open(file_path, "rb")
    if not file then
        return false, "failed to open file: " .. file_path
                      .. ", error info:" .. err
    end

    local dns_addrs = {}
    for line in file:lines() do
        local addr, n = line:gsub("^nameserver%s+(%d+%.%d+%.%d+%.%d+)%s*$",
                                  "%1")
        if n == 1 then
            dns_addrs[#dns_addrs + 1] = addr
        end
    end

    file:close()

    return dns_addrs
end


return _M
