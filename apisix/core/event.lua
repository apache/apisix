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

local CONST = {
    BUILD_ROUTER = 1,
}

local _M = {
    CONST = CONST,
}

local events = {}


function _M.push(type, ...)
    local handler = events[type]
    if handler then
        handler(...)
    end
end

function _M.register(type, handler)
    -- TODO: we can register more than one handler
    events[type] = handler
end

function _M.unregister(type)
    events[type] = nil
end

return _M
