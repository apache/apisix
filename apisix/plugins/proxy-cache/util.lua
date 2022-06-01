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

local core = require("apisix.core")
local ngx_re = require("ngx.re")
local tab_concat = table.concat
local string = string
local io_open = io.open
local io_close = io.close
local ngx = ngx
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber

local _M = {}

local tmp = {}
function _M.generate_complex_value(data, ctx)
    core.table.clear(tmp)

    core.log.info("proxy-cache complex value: ", core.json.delay_encode(data))
    for i, value in ipairs(data) do
        core.log.info("proxy-cache complex value index-", i, ": ", value)

        if string.byte(value, 1, 1) == string.byte('$') then
            tmp[i] = ctx.var[string.sub(value, 2)] or ""
        else
            tmp[i] = value
        end
    end

    return tab_concat(tmp, "")
end


-- check whether the request method match the user defined.
function _M.match_method(conf, ctx)
    for _, method in ipairs(conf.cache_method) do
        if method == ctx.var.request_method then
            return true
        end
    end

    return false
end


-- check whether the response status match the user defined.
function _M.match_status(conf, ctx)
    for _, status in ipairs(conf.cache_http_status) do
        if status == ngx.status then
            return true
        end
    end

    return false
end


function _M.file_exists(name)
    local f = io_open(name, "r")
    if f ~= nil then
        io_close(f)
        return true
    end
    return false
end


function _M.generate_cache_filename(cache_path, cache_levels, cache_key)
    local md5sum = ngx.md5(cache_key)
    local levels = ngx_re.split(cache_levels, ":")
    local filename = ""

    local index = #md5sum
    for k, v in pairs(levels) do
        local length = tonumber(v)
        index = index - length
        filename = filename .. md5sum:sub(index+1, index+length) .. "/"
    end
    if cache_path:sub(-1) ~= "/" then
        cache_path = cache_path .. "/"
    end
    filename = cache_path .. filename .. md5sum
    return filename
end

return _M
