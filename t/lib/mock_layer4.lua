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
local json_decode = require("toolkit.json").decode
local json_encode = require("toolkit.json").encode
local ngx = ngx
local socket = ngx.req.socket

local _M = {}

function _M.dogstatsd()
    local sock, err = socket()
    if not sock then
        core.log.error("failed to get the request socket: ", err)
        return
     end

    while true do
        local data, err = sock:receive()

        if not data then
            if err and err ~= "no more data" then
                core.log.error("socket error, returning: ", err)
            end
            return
        end
        core.log.warn("message received: ", data)
    end
end


function _M.loggly()
    local sock, err = socket()
    if not sock then
        core.log.error("failed to get the request socket: ", err)
        return
     end

    while true do
        local data, err = sock:receive()

        if not data then
            if err and err ~= "no more data" then
                core.log.error("socket error, returning: ", err)
            end
            return
        end
        local m, err = ngx.re.match(data, "(^[ -~]*] )([ -~]*)")
        if not m then
            core.log.error("unknown data received, failed to extract: ", err)
            return
        end
        if #m ~= 2 then
            core.log.error("failed to match two (header, log body) subgroups", #m)
        end
        -- m[1] contains syslog header header <14>1 .... & m[2] contains actual log body
        local logbody = json_decode(m[2])
        -- order keys
        logbody = json_encode(logbody)
        core.log.warn("message received: ", m[1] .. logbody)
    end
end

return _M
