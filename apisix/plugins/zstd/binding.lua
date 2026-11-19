--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied.  See the License for the
-- specific language governing permissions and limitations
-- under the License.
--

-- Minimal LuaJIT FFI binding to libzstd's streaming API, following the
-- surface of brotli-ffi (compressor:new / compress / flush / finish,
-- decompressor:new / decompress / finish). Requires the system libzstd.
local ffi = require("ffi")

local tonumber = tonumber
local setmetatable = setmetatable
local concat = table.concat

local zstd = ffi.load("zstd")

ffi.cdef[[
typedef struct ZSTD_CCtx_s ZSTD_CCtx;
typedef struct ZSTD_DCtx_s ZSTD_DCtx;

typedef struct {
    const void *src;
    size_t size;
    size_t pos;
} ZSTD_inBuffer;

typedef struct {
    void *dst;
    size_t size;
    size_t pos;
} ZSTD_outBuffer;

ZSTD_CCtx *ZSTD_createCCtx(void);
size_t ZSTD_freeCCtx(ZSTD_CCtx *cctx);
ZSTD_DCtx *ZSTD_createDCtx(void);
size_t ZSTD_freeDCtx(ZSTD_DCtx *dctx);

size_t ZSTD_compressStream2(ZSTD_CCtx *cctx, ZSTD_outBuffer *output,
                            ZSTD_inBuffer *input, int endOp);
size_t ZSTD_decompressStream(ZSTD_DCtx *dctx, ZSTD_outBuffer *output,
                             ZSTD_inBuffer *input);
size_t ZSTD_CCtx_setParameter(ZSTD_CCtx *cctx, int cParameter, unsigned value);
unsigned ZSTD_isError(size_t code);
const char *ZSTD_getErrorName(size_t code);
size_t ZSTD_CStreamOutSize(void);
size_t ZSTD_DStreamOutSize(void);
]]

-- from zstd.h
local ZSTD_e_continue = 0
local ZSTD_e_flush = 1
local ZSTD_e_end = 2
local ZSTD_c_compressionLevel = 100


local function last_error(ret)
    return ffi.string(zstd.ZSTD_getErrorName(ret))
end


local Compressor = {}

local compressor_gc = {
    __index = Compressor,
    __gc = function(self)
        if self.cctx ~= nil then
            zstd.ZSTD_freeCCtx(self.cctx)
            self.cctx = nil
        end
    end,
}

function Compressor.new(_, opts)
    opts = opts or {}

    local cctx = zstd.ZSTD_createCCtx()
    if cctx == nil then
        return nil, "failed to create zstd compression context"
    end

    local level = opts.level or opts.quality or 3
    local ret = zstd.ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, level)
    if zstd.ZSTD_isError(ret) ~= 0 then
        zstd.ZSTD_freeCCtx(cctx)
        return nil, "failed to set compression level " .. level .. ": "
                    .. last_error(ret)
    end

    local out_size = tonumber(zstd.ZSTD_CStreamOutSize())
    local self = setmetatable({
        cctx = cctx,
        out_size = out_size,
        out_buf = ffi.new("char[?]", out_size),
        in_buf = ffi.new("ZSTD_inBuffer[1]"),
        out = ffi.new("ZSTD_outBuffer[1]"),
    }, compressor_gc)

    return self
end


local function run_compression(self, chunk, end_op)
    local in_buf = self.in_buf
    local out = self.out
    local out_buf = self.out_buf
    local out_size = self.out_size

    in_buf[0].src = ffi.cast("const char *", chunk)
    in_buf[0].size = #chunk
    in_buf[0].pos = 0

    local parts = {}
    local n = 0

    while true do
        out[0].dst = ffi.cast("char *", out_buf)
        out[0].size = out_size
        out[0].pos = 0

        local ret = zstd.ZSTD_compressStream2(self.cctx, out, in_buf, end_op)
        if zstd.ZSTD_isError(ret) ~= 0 then
            return nil, last_error(ret)
        end

        if out[0].pos > 0 then
            n = n + 1
            parts[n] = ffi.string(out_buf, out[0].pos)
        end

        if end_op == ZSTD_e_continue then
            if in_buf[0].pos >= in_buf[0].size then
                break
            end
        else
            -- for flush/end the return value is 0 once all pending data
            -- has been written
            if ret == 0 then
                break
            end
        end
    end

    return concat(parts)
end


function Compressor.compress(self, chunk)
    return run_compression(self, chunk, ZSTD_e_continue)
end


function Compressor.flush(self)
    return run_compression(self, "", ZSTD_e_flush)
end


function Compressor.finish(self)
    return run_compression(self, "", ZSTD_e_end)
end


function Compressor.free(self)
    if self.cctx ~= nil then
        zstd.ZSTD_freeCCtx(self.cctx)
        self.cctx = nil
    end
end


local Decompressor = {}

local decompressor_gc = {
    __index = Decompressor,
    __gc = function(self)
        if self.dctx ~= nil then
            zstd.ZSTD_freeDCtx(self.dctx)
            self.dctx = nil
        end
    end,
}

function Decompressor.new(_)
    local dctx = zstd.ZSTD_createDCtx()
    if dctx == nil then
        return nil, "failed to create zstd decompression context"
    end

    local out_size = tonumber(zstd.ZSTD_DStreamOutSize())
    local self = setmetatable({
        dctx = dctx,
        out_size = out_size,
        out_buf = ffi.new("char[?]", out_size),
        in_buf = ffi.new("ZSTD_inBuffer[1]"),
        out = ffi.new("ZSTD_outBuffer[1]"),
    }, decompressor_gc)

    return self
end


local function run_decompression(self, chunk)
    local in_buf = self.in_buf
    local out = self.out
    local out_buf = self.out_buf
    local out_size = self.out_size

    in_buf[0].src = ffi.cast("const char *", chunk)
    in_buf[0].size = #chunk
    in_buf[0].pos = 0

    local parts = {}
    local n = 0

    while true do
        out[0].dst = ffi.cast("char *", out_buf)
        out[0].size = out_size
        out[0].pos = 0

        local ret = zstd.ZSTD_decompressStream(self.dctx, out, in_buf)
        if zstd.ZSTD_isError(ret) ~= 0 then
            return nil, last_error(ret)
        end

        if out[0].pos > 0 then
            n = n + 1
            parts[n] = ffi.string(out_buf, out[0].pos)
        end

        -- stop once all input is consumed and the output buffer was not
        -- filled completely, i.e. no further progress can be made without
        -- new input
        if in_buf[0].pos >= in_buf[0].size and out[0].pos < out_size then
            break
        end
    end

    return concat(parts)
end


function Decompressor.decompress(self, chunk)
    return run_decompression(self, chunk)
end


function Decompressor.finish(self)
    return run_decompression(self, "")
end


function Decompressor.free(self)
    if self.dctx ~= nil then
        zstd.ZSTD_freeDCtx(self.dctx)
        self.dctx = nil
    end
end


local _M = {
    version = "0.1",
}
_M.compressor = Compressor
_M.decompressor = Decompressor

return _M
