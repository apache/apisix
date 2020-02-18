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
local encode_json = require("cjson.safe").encode
local ngx = ngx
local ngx_print = ngx.print
local ngx_header = ngx.header
local error = error
local select = select
local type = type
local ngx_exit = ngx.exit
local insert_tab = table.insert
local concat_tab = table.concat
local str_sub = string.sub
local tonumber = tonumber
local pairs = pairs

local _M = {version = 0.1}


local resp_exit
do
    local t = {}
    local idx = 1

function resp_exit(code, ...)
    idx = 0

    if code and type(code) ~= "number" then
        insert_tab(t, code)
        code = nil
    end

    if code then
        ngx.status = code
    end

    for i = 1, select('#', ...) do
        local v = select(i, ...)
        if type(v) == "table" then
            local body, err = encode_json(v)
            if err then
                error("failed to encode data: " .. err, -2)
            else
                idx = idx + 1
                insert_tab(t, idx, body .. "\n")
            end

        elseif v ~= nil then
            idx = idx + 1
            insert_tab(t, idx, v)
        end
    end

    if idx > 0 then
        ngx_print(concat_tab(t, "", 1, idx))
    end

    if code then
        return ngx_exit(code)
    end
end

end -- do
_M.exit = resp_exit


function _M.say(...)
    resp_exit(nil, ...)
end


function _M.set_header(...)
    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    local count = select('#', ...)
    if count == 1 then
        local headers = select(1, ...)
        if type(headers) ~= "table" then
            error("should be a table if only one argument", 2)
        end

        for k, v in pairs(headers) do
            ngx_header[k] = v
        end

        return
    end

    for i = 1, count, 2 do
        ngx_header[select(i, ...)] = select(i + 1, ...)
    end
end


function _M.get_upstream_status(ctx)
    -- $upstream_status maybe including mutiple status, only need the last one
    return tonumber(str_sub(ctx.var.upstream_status or "", -3))
end

return _M
