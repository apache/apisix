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
local tab_new = table.new
local tab_insert = table.insert
local tab_clear = table.clear

local circular_queue = {}
circular_queue.__index = circular_queue


function circular_queue:new(_capacity)
    _capacity = _capacity or 100
    if _capacity < 1 then
        _capacity = 1
    end

    local obj = {
        _capacity = _capacity,
        front = 1,
        rear = 1,
        data = tab_new(_capacity, 0),
        size = 0,
    }
    setmetatable(obj, self)
    return obj
end


function circular_queue:is_empty()
    return self.size == 0
end


function circular_queue:is_full()
    return self.size == self._capacity
end


function circular_queue:len()
    return self.size
end


function circular_queue:capacity()
    return self._capacity
end


function circular_queue:reset(new_capacity)
    self:clear()
    self._capacity = new_capacity or self._capacity
    if self._capacity < 1 then
        self._capacity = 1
    end
end


function circular_queue:enqueue(element)
    if self:is_full() then
        self.front = self.front % self._capacity + 1
    else
        self.size = self.size + 1
    end

    self.data[self.rear] = element
    self.rear = self.rear % self._capacity + 1
end


function circular_queue:dequeue()
    if self:is_empty() then
        return nil
    end
    local element = self.data[self.front]
    self.data[self.front] = nil
    self.front = self.front % self._capacity + 1
    self.size = self.size - 1
    return element
end


function circular_queue:peek()
    if self:is_empty() then
        return nil
    end
    return self.data[self.front]
end


function circular_queue:clear()
    self.front = 1
    self.rear = 1
    self.size = 0
    tab_clear(self.data)
end


function circular_queue:traverse()
    local elements = {}
    if self:is_empty() then
        return elements
    end
    local idx = self.front
    for i = 1, self.size do
        tab_insert(elements, self.data[idx])
        idx = idx % self._capacity + 1
    end
    return elements
end


function circular_queue:drain()
    local elements = self:traverse()
    self:clear()
    return elements
end


return circular_queue
