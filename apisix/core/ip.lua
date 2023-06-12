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

--- IP match and verify module.
--
-- @module core.ip

local json = require("apisix.core.json")
local log = require("apisix.core.log")
local ipmatcher = require("resty.ipmatcher")
local str_sub   = string.sub
local str_find  = require("apisix.core.string").find
local tonumber  = tonumber


local _M = {}


function _M.create_ip_matcher(ip_list)
    local ip, err = ipmatcher.new(ip_list)
    if not ip then
        log.error("failed to create ip matcher: ", err,
                  " ip list: ", json.delay_encode(ip_list))
        return nil
    end

    return ip
end

---
-- Verify that the given ip is a valid ip or cidr.
--
-- @function core.ip.validate_cidr_or_ip
-- @tparam string ip IP or cidr.
-- @treturn boolean True if the given ip is a valid ip or cidr, false otherwise.
-- @usage
-- local ip1 = core.ip.validate_cidr_or_ip("127.0.0.1") -- true
-- local cidr = core.ip.validate_cidr_or_ip("113.74.26.106/24") -- true
-- local ip2 = core.ip.validate_cidr_or_ip("113.74.26.666") -- false
function _M.validate_cidr_or_ip(ip)
    local mask = 0
    local sep_pos = str_find(ip, "/")
    if sep_pos then
        mask = str_sub(ip, sep_pos + 1)
        mask = tonumber(mask)
        if mask < 0 or mask > 128 then
            return false
        end
        ip = str_sub(ip, 1, sep_pos - 1)
    end

    if ipmatcher.parse_ipv4(ip) then
        if mask < 0 or mask > 32 then
            return false
        end
        return true
    end

    if mask < 0 or mask > 128 then
        return false
    end
    return ipmatcher.parse_ipv6(ip)
end


return _M
