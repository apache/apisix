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
-- @module cli.ip

local mediador_ip = require("resty.mediador.ip")
local setmetatable = setmetatable


local _M = {}
local mt = { __index = _M }


---
-- create a instance of module cli.ip
--
-- @function cli.ip:new
-- @tparam string ip IP or CIDR.
-- @treturn instance of module if the given ip valid, nil and error message otherwise.
function _M.new(self, ip)
    if not mediador_ip.valid(ip) then
        return nil, "invalid ip"
    end

    local _ip = mediador_ip.parse(ip)

    return setmetatable({ _ip = _ip }, mt)
end


---
-- Is that the given ip loopback?
--
-- @function cli.ip:is_loopback
-- @treturn boolean True if the given ip is the loopback, false otherwise.
function _M.is_loopback(self)
    return self._ip and "loopback" == self._ip:range()
end

---
-- Is that the given ip unspecified?
--
-- @function cli.ip:is_unspecified
-- @treturn boolean True if the given ip is all the unspecified, false otherwise.
function _M.is_unspecified(self)
    return self._ip and "unspecified" == self._ip:range()
end


return _M
