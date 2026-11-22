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
local inflate_gzip = require("apisix.utils.gzip").inflate_gzip
local str_buffer = require("string.buffer")
local is_br_libs_loaded, brotli = pcall(require, "brotli")
local _M = {}


-- Every decoder takes (data, max_output). With max_output set, data may be a
-- cut prefix of the stream: decoding stops without an error where data ends or
-- once max_output bytes are decoded, and returns at most max_output bytes.
local function gzip_decode(data, max_output)
    return inflate_gzip(data, nil, nil, max_output, max_output ~= nil)
end


local content_decode_funcs = {
    gzip = gzip_decode,
}


local function brotli_stream_decode(read_inputs, write_outputs, partial)
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
        elseif partial then
            return true, nil
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


local function brotli_decode(data, max_output)
    local inputs = str_buffer.new():set(data)
    local outputs = str_buffer.new()

    local read_inputs = function(size)
        if max_output and #outputs >= max_output then
            return nil
        end
        local data = inputs:get(size)
        if data == "" then
            return nil
        end
        return data
    end

    local write_outputs = function(data)
        return outputs:put(data)
    end

    local ok, err = brotli_stream_decode(read_inputs, write_outputs, max_output ~= nil)
    if not ok then
        return nil, "brotli decode err: " .. err
    end

    return outputs:get(max_output)
end

if is_br_libs_loaded then
    content_decode_funcs.br = brotli_decode
end


function _M.dispatch_decoder(response_encoding)
    return content_decode_funcs[response_encoding]
end


return _M
