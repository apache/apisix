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

local require = require
local pcall = pcall
local open = io.open
local popen = io.popen
local close = io.close
local exit = os.exit
local stderr = io.stderr
local str_format = string.format
local tonumber = tonumber
local io = io
local ipairs = ipairs
local assert = assert

local _M = {}


-- Note: The `execute_cmd` return value will have a line break at the end,
-- it is recommended to use the `trim` function to handle the return value.
local function execute_cmd(cmd)
    local t, err = popen(cmd)
    if not t then
        return nil, "failed to execute command: "
                    .. cmd .. ", error info: " .. err
    end

    local data, err = t:read("*all")
    t:close()

    if not data then
        return nil, "failed to read execution result of: "
                    .. cmd .. ", error info: " .. err
    end

    return data
end
_M.execute_cmd = execute_cmd


-- For commands which stdout would be always be empty,
-- forward stderr to stdout to get the error msg
function _M.execute_cmd_with_error(cmd)
    return execute_cmd(cmd .. " 2>&1")
end


function _M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end


function _M.split(self, sep)
    local sep, fields = sep or ":", {}
    local pattern = str_format("([^%s]+)", sep)

    self:gsub(pattern, function(c) fields[#fields + 1] = c end)

    return fields
end


function _M.read_file(file_path)
    local file, err = open(file_path, "rb")
    if not file then
        return false, "failed to open file: " .. file_path .. ", error info:" .. err
    end

    local data, err = file:read("*all")
    file:close()
    if not data then
        return false, "failed to read file: " .. file_path .. ", error info:" .. err
    end

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


function _M.write_file(file_path, data)
    local file, err = open(file_path, "w+")
    if not file then
        return false, "failed to open file: "
                      .. file_path
                      .. ", error info:"
                      .. err
    end

    local ok, err = file:write(data)
    file:close()
    if not ok then
        return false, "failed to write file: "
                      .. file_path
                      .. ", error info:"
                      .. err
    end
    return true
end


function _M.file_exists(file_path)
    local f = open(file_path, "r")
    return f ~= nil and close(f)
end

do
    local trusted_certs_paths = {
        "/etc/ssl/certs/ca-certificates.crt",                -- Debian/Ubuntu/Gentoo
        "/etc/pki/tls/certs/ca-bundle.crt",                  -- Fedora/RHEL 6
        "/etc/ssl/ca-bundle.pem",                            -- OpenSUSE
        "/etc/pki/tls/cacert.pem",                           -- OpenELEC
        "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", -- CentOS/RHEL 7
        "/etc/ssl/cert.pem",                                 -- OpenBSD, Alpine
    }

    -- Check if a file exists using Lua's built-in `io.open`
    local function file_exists(path)
        local file = io.open(path, "r")
        if file then
            file:close()
            return true
        else
            return false
        end
    end

    function _M.get_system_trusted_certs_filepath()
        for _, path in ipairs(trusted_certs_paths) do
            if file_exists(path) then
                return path
            end
        end

        return nil,
            "Could not find trusted certs file in " ..
            "any of the `system`-predefined locations. " ..
            "Please install a certs file there or set " ..
            "`lua_ssl_trusted_certificate` to a " ..
            "specific file path instead of `system`"
    end
end


local function ensure_dir(path)
    -- Extract directory from path
    local dir = path:match("(.*/)")
    if dir then
        -- Try to create directory recursively.
        -- This uses "mkdir -p" to avoid error if the directory already exists.
        local ok = os.execute("mkdir -p " .. dir)
        if not ok then
            error("Failed to create directory: " .. dir)
        end
    end
end

function _M.gen_trusted_certs_combined_file(combined_filepath, paths)
    -- Ensure the directory for combined_filepath exists.
    ensure_dir(combined_filepath)

    local combined_file, err = io.open(combined_filepath, "w")
    if not combined_file then
        error("Failed to open or create combined file at " .. combined_filepath ..
              ". Error: " .. tostring(err))
    end

    for _, path in ipairs(paths) do
        local cert_file, cert_err = io.open(path, "r")
        if not cert_file then
            error("Failed to open certificate file " .. path .. ": " .. tostring(cert_err))
        end
        local data = cert_file:read("*a") or ""
        combined_file:write(data)
        combined_file:write("\n")
        cert_file:close()
    end
    combined_file:close()
end


return _M
