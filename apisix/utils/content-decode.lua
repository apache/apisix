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
local zlib = require("ffi-zlib")
local str_buffer = require("string.buffer")
local is_br_libs_loaded, brotli = pcall(require, "brotli")
local content_decode_funcs = {}
local _M = {}


local function inflate_gzip(data)
    local inputs = str_buffer.new():set(data)
    local outputs = str_buffer.new()

    local read_inputs = function(size)
        local data = inputs:get(size)
        if data == "" then
            return nil
        end
        return data
    end

    local write_outputs = function(data)
        return outputs:put(data)
    end

    local ok, err = zlib.inflateGzip(read_inputs, write_outputs)
    if not ok then
        return nil, "inflate gzip err: " .. err
    end

    return outputs:get()
end
content_decode_funcs.gzip = inflate_gzip


local function brotli_stream_decode(read_inputs, write_outputs)
    -- read 64k data per times
    local read_size = 64 * 1024
    local decompressor = brotli.decompressor:new()

    local chunk, ok, res
    repeat
        chunk = read_inputs(read_size)
        if chunk then
            ok, res = pcall(function()
                return decompressor:decompress(chunk)
            end)
        else
            ok, res = pcall(function()
                return decompressor:finish()
            end)
        end
        if not ok then
            return false, res
        end
        write_outputs(res)
    until not chunk

    return true, nil
end


local function brotli_decode(data)
    local inputs = str_buffer.new():set(data)
    local outputs = str_buffer.new()

    local read_inputs = function(size)
        local data = inputs:get(size)
        if data == "" then
            return nil
        end
        return data
    end

    local write_outputs = function(data)
        return outputs:put(data)
    end

    local ok, err = brotli_stream_decode(read_inputs, write_outputs)
    if not ok then
        return nil, "brotli decode err: " .. err
    end

    return outputs:get()
end

if is_br_libs_loaded then
    content_decode_funcs.br = brotli_decode
end


function _M.dispatch_decoder(response_encoding)
    return content_decode_funcs[response_encoding]
end


return _M
