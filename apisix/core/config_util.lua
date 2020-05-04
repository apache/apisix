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
local setmetatable = setmetatable
local type = type


local _M = {}


local function _iterate_values(self, tab)
    while true do
        self.idx = self.idx + 1
        local v = tab[self.idx]
        if type(v) == "table" then
            return self.idx, v
        end
        if v == nil then
            return nil, nil
        end
        -- skip the tombstone
    end
end


function _M.iterate_values(tab)
    local iter = setmetatable({idx = 0}, {__call = _iterate_values})
    return iter, tab, 0
end


return _M
