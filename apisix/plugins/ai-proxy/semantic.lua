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

-- Pure-lua vector math for semantic routing: no apisix.core dependency so it can
-- be unit-tested standalone. Vectors are plain arrays of numbers.
local sqrt = math.sqrt

local _M = {}


-- Return the unit vector of `vec`. A zero vector normalizes to zeros (no NaN).
function _M.normalize(vec)
    local sum = 0
    for i = 1, #vec do
        sum = sum + vec[i] * vec[i]
    end
    local norm = sqrt(sum)
    local out = {}
    if norm == 0 then
        for i = 1, #vec do
            out[i] = 0
        end
        return out
    end
    for i = 1, #vec do
        out[i] = vec[i] / norm
    end
    return out
end


-- Dot product. On pre-normalized vectors this equals cosine similarity.
function _M.dot(a, b)
    local sum = 0
    for i = 1, #a do
        sum = sum + a[i] * b[i]
    end
    return sum
end


-- Cosine similarity in [-1, 1]. Normalizes both inputs; for hot paths prefer
-- pre-normalizing once and calling dot() directly.
function _M.cosine(a, b)
    return _M.dot(_M.normalize(a), _M.normalize(b))
end


-- Score an instance from its per-example similarities.
-- `examples` are alternative phrasings of one intent, so the question is whether
-- ANY of them matches: take the best. Averaging would dilute a dead-on example
-- with the instance's broader ones, and would make adding an example lower the
-- instance's score.
function _M.max(scores)
    local n = #scores
    if n == 0 then
        return nil
    end
    local m = scores[1]
    for i = 2, n do
        if scores[i] > m then
            m = scores[i]
        end
    end
    return m
end


return _M
