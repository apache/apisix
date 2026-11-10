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
local zlib = require("ffi-zlib")
local str_buffer = require("string.buffer")
local str_sub = string.sub
local Z_OK = zlib.zlib.Z_OK
local DEFAULT_CHUNK = 16384
local _M = {}


-- A gzip stream may carry several members concatenated (RFC 1952 section 2.2),
-- and one inflate run stops at the end of the first one. Every member is
-- inflated in turn, so a concatenated payload is never silently truncated and
-- max_output bounds their total. max_output aborts the stream as soon as the
-- running total crosses it, so an oversized payload is never fully buffered;
-- the third return value flags that case. Bytes left after the last member are
-- fed to a further inflate, which rejects them.
function _M.inflate_gzip(data, buf_size, opts, max_output)
    buf_size = buf_size or DEFAULT_CHUNK
    local outputs = str_buffer.new()
    local written = 0
    local exceeded = false
    local pos = 1

    local read_inputs = function(size)
        if pos > #data then
            return nil
        end
        local chunk = str_sub(data, pos, pos + size - 1)
        pos = pos + #chunk
        return chunk
    end

    local write_outputs = function(chunk)
        if max_output then
            written = written + #chunk
            if written > max_output then
                exceeded = true
                return nil, "output size limit exceeded"
            end
        end
        return outputs:put(chunk)
    end

    repeat
        local stream, inbuf, outbuf = zlib.createStream(buf_size)

        local init = zlib.initInflate(stream, opts)
        if init ~= Z_OK then
            zlib.zlib.inflateEnd(stream)
            return nil, "inflate gzip err: INIT: " .. zlib.zlib_err(init)
        end

        local ok, err = zlib.inflate(read_inputs, write_outputs, buf_size,
                                     stream, inbuf, outbuf)
        if not ok then
            if exceeded then
                return nil, "inflated data is greater than the maximum size "
                            .. max_output .. " allowed", true
            end
            return nil, "inflate gzip err: " .. err
        end

        -- the member stopped short of the bytes that begin the next one
        pos = pos - stream.avail_in
    until pos > #data

    return outputs:get()
end


function _M.deflate_gzip(data, buf_size, opts)
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

    local ok, err = zlib.deflateGzip(read_inputs, write_outputs, buf_size, opts)
    if not ok then
        return nil, "deflate gzip err: " .. err
    end

    return outputs:get()
end

return _M
