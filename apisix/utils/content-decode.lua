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
local brotli = require("apisix.utils.brotli")
local inflate_gzip = require("apisix.utils.gzip").inflate_gzip
local _M = {}


-- Every decoder takes (data, max_output). With max_output set, data may be a
-- cut prefix of the stream: decoding stops without an error where data ends or
-- once max_output bytes are decoded, and returns at most max_output bytes.
local function gzip_decode(data, max_output)
    return inflate_gzip(data, nil, nil, max_output, max_output ~= nil)
end


local function brotli_decode(data, max_output)
    local decoded, err = brotli.get().decode(data, max_output)
    if not decoded then
        return nil, "brotli decode err: " .. err
    end
    return decoded
end


function _M.dispatch_decoder(response_encoding)
    if response_encoding == "gzip" then
        return gzip_decode
    end
    if response_encoding == "br" then
        if brotli.get() then
            return brotli_decode
        end
        return nil, true
    end
end


return _M
