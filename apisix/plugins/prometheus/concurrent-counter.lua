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
local table = require("apisix.core.table")

local ngx = ngx
local tostring = tostring
local pairs = pairs
local math = math

local concurrency = {}
local data = {
    code = nil,
    body = nil,
}

local _M = {}

local function get_count_after_clean(max_ttl)
    max_ttl = max_ttl or 30
    local cur_time = ngx.time()
    local copied_concurrency = table.clone(concurrency)

    for ctx_str, reg_time in pairs(copied_concurrency) do
        if math.abs(cur_time - reg_time) > max_ttl then
            concurrency[ctx_str] = nil
        end
    end

    return table.nkeys(concurrency)
end
_M.clean_and_count = get_count_after_clean

function _M.reg(ctx, max_ttl)
    local ctx_str = tostring(ctx)
    concurrency[ctx_str] = ngx.time()

    return get_count_after_clean(max_ttl)
end

function _M.unreg(ctx)
    local ctx_str = tostring(ctx)
    concurrency[ctx_str] = nil
end

function _M.set_data(code, body)
    data.code = code
    data.body = body
end

function _M.get_data()
    return data.code, data.body
end

function _M.reset_data()
    data.code = nil
    data.body = nil
end

return _M
