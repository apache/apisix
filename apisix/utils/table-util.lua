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

local _M = {}

local function merge(origin, extend)
    for k,v in pairs(extend) do
        if type(v) == "table" then
            if type(origin[k] or false) == "table" then
                merge(origin[k] or {}, extend[k] or {})
            else
                origin[k] = v
            end
        elseif v == ngx.null then
            origin[k] = nil
        else
            origin[k] = v
        end
    end

    return origin
end

_M.merge = merge

return _M
