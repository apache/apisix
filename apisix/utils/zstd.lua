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

-- zstd compression implemented by FFI, which requires libzstd to be
-- installed on the host (e.g. libzstd1 on Debian/Ubuntu, libzstd on CentOS).
local ffi = require("ffi")
local pcall = pcall
local ffi_load = ffi.load
local ffi_new = ffi.new
local ffi_copy = ffi.copy
local ffi_string = ffi.string
local type = type
local tonumber = tonumber


local DEFAULT_COMPRESS_LEVEL = 3 -- ZSTD_CLEVEL_DEFAULT
-- libzstd may only ship the versioned soname, so try all the common names
local LIB_NAMES = { "libzstd.so.1", "zstd", "libzstd" }

local _M = {}


ffi.cdef[[
    size_t ZSTD_compressBound(size_t srcSize);
    size_t ZSTD_compress(void *dst, size_t dstCapacity,
                         const void *src, size_t srcSize, int compressionLevel);
    unsigned ZSTD_isError(size_t code);
    const char *ZSTD_getErrorName(size_t code);
]]


local libzstd
local libzstd_err
local libzstd_loaded


-- load libzstd lazily and only once, the result (including the failure)
-- is cached so that we never call dlopen again.
local function load_libzstd()
    if libzstd_loaded then
        return libzstd, libzstd_err
    end

    libzstd_loaded = true
    for i = 1, #LIB_NAMES do
        local ok, lib = pcall(ffi_load, LIB_NAMES[i])
        if ok and lib then
            -- make sure the loaded library exports the symbols we need
            local ok_sym = pcall(function()
                return lib.ZSTD_compressBound(1)
            end)
            if ok_sym then
                libzstd = lib
                return libzstd
            end
        end
    end

    libzstd_err = "failed to load libzstd, please make sure it is installed"
    return nil, libzstd_err
end


-- tells whether zstd compression is usable on the current host
function _M.available()
    local lib = load_libzstd()
    return lib ~= nil
end


-- compress the given data into a zstd frame
-- returns the compressed data, or nil and an error message when the data
-- can not be compressed (e.g. libzstd is not installed)
function _M.compress(data, level)
    if type(data) ~= "string" then
        return nil, "invalid data type: " .. type(data)
    end

    if level == nil then
        level = DEFAULT_COMPRESS_LEVEL
    elseif type(level) ~= "number" then
        return nil, "invalid compression level"
    end

    local lib, err = load_libzstd()
    if not lib then
        return nil, err
    end

    local src_size = #data
    local capacity = tonumber(lib.ZSTD_compressBound(src_size))
    local src = ffi_new("char[?]", src_size)
    local dst = ffi_new("char[?]", capacity)
    ffi_copy(src, data, src_size)

    local compressed_size = tonumber(lib.ZSTD_compress(dst, capacity, src, src_size, level))
    if lib.ZSTD_isError(compressed_size) ~= 0 then
        return nil, "failed to compress the data: "
                    .. ffi_string(lib.ZSTD_getErrorName(compressed_size))
    end

    return ffi_string(dst, compressed_size)
end


return _M
