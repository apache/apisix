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
local mt = { __index = _M }

function _M.new()
    local self = {
        _data = {},
        _n = 0,
    }
    return setmetatable(self, mt)
end


function _M.push(self, value)
    self._n = self._n + 1
    self._data[self._n] = value
end


function _M.pop(self)
    if self._n == 0 then
        return nil
    end

    local value = self._data[self._n]
    self._data[self._n] = nil
    self._n = self._n - 1
    return value
end


function _M.peek(self)
    if self._n == 0 then
        return nil
    end

    return self._data[self._n]
end


function _M.is_empty(self)
    return self._n == 0
end


function _M.size(self)
    return self._n
end


function _M.clear(self)
    for i = 1, self._n do
        self._data[i] = nil
    end
    self._n = 0
end


return _M

