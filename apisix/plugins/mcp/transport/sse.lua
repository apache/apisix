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
local type         = type
local core         = require("apisix.core")

local _M = {}
local mt = { __index = _M }


function _M.new()
    return setmetatable({}, mt)
end


function _M.send(self, message, event_type)
    local data = type(message) == "table" and core.json.encode(message) or message
    local ok, err = ngx.print("event: " .. (event_type or "message") .. "\ndata: " .. data .. "\n\n")
    if not ok then
        return ok, "failed to write buffer: " .. err
    end
    return ngx.flush(true)
end


return _M
