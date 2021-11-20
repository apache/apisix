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
local assert = assert
local type = type
local setmetatable = setmetatable
local math = math


local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    return setmetatable({}, mt)
end

function _M.sample(self, sample_ratio)
    assert(type(sample_ratio) == "number" and
           sample_ratio >= 0 and sample_ratio <= 1, "invalid sample_ratio")
    return math.random() < sample_ratio
end


return _M
