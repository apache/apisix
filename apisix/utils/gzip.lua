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
local _M = {}


-- max_output aborts the stream once the inflated data exceeds it, so an
-- oversized payload is never fully buffered. Third return value flags that case.
function _M.inflate_gzip(data, buf_size, opts, max_output)
    local inputs = str_buffer.new():set(data)
    local outputs = str_buffer.new()
    local written = 0
    local exceeded = false

    local read_inputs = function(size)
        local data = inputs:get(size)
        if data == "" then
            return nil
        end
        return data
    end

    local write_outputs = function(data)
        if max_output then
            written = written + #data
            if written > max_output then
                exceeded = true
                return nil, "output size limit exceeded"
            end
        end
        return outputs:put(data)
    end

    local ok, err = zlib.inflateGzip(read_inputs, write_outputs, buf_size, opts)
    if not ok then
        if exceeded then
            return nil, "inflated data is greater than the maximum size "
                        .. max_output .. " allowed", true
        end
        return nil, "inflate gzip err: " .. err
    end

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
