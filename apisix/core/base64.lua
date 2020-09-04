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
local bit = require("bit")
local table = table
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift

local _M = {}

local base64_tab = {
	[0]='A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
	'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
	'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
	'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
	'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
	'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
	'w', 'x', 'y', 'z', '0', '1', '2', '3',
	'4', '5', '6', '7', '8', '9', '+', '/',
}
local base64_pad = '='

local function rand(char, width, dis)
    return rshift(band(char, width), dis)
end
local function land(char, width, dis)
    return lshift(band(char, width), dis)
end

function _M.encode(str)
    local res = {}
    local pos, len = 1, #str
    while pos <= len do
        res[#res+1] = base64_tab[rand(str:byte(pos+0), 0xfc, 2)]
        if pos+1 <= len then
            res[#res+1] = base64_tab[land(str:byte(pos+0), 0x03, 4)
                                   + rand(str:byte(pos+1), 0xf0, 4)]
            if pos+2 <= len then
                res[#res+1] = base64_tab[land(str:byte(pos+1), 0x0f, 2)
                                       + rand(str:byte(pos+2), 0xc0, 6)]
                res[#res+1] = base64_tab[band(str:byte(pos+2), 0x3f)]
            else
                res[#res+1] = base64_tab[land(str:byte(pos+1), 0x0f, 2)]
                res[#res+1] = base64_pad
            end
        else
            res[#res+1] = base64_tab[land(str:byte(pos+0), 0x03, 4)]
            res[#res+1] = base64_pad
            res[#res+1] = base64_pad
        end
        pos = pos + 3
    end

    return table.concat(res)
end

return _M
