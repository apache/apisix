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
local newproxy     = newproxy
local getmetatable = getmetatable
local setmetatable = setmetatable
local select       = select
local new_tab      = require("table.new")
local nkeys        = require("table.nkeys")
local pairs        = pairs
local type         = type
local ngx_re       = require("ngx.re")


local _M = {
    version = 0.2,
    new     = new_tab,
    clear   = require("table.clear"),
    nkeys   = nkeys,
    insert  = table.insert,
    concat  = table.concat,
    sort    = table.sort,
    clone   = require("table.clone"),
    isarray = require("table.isarray"),
}


setmetatable(_M, {__index = table})


function _M.insert_tail(tab, ...)
    local idx = #tab
    for i = 1, select('#', ...) do
        idx = idx + 1
        tab[idx] = select(i, ...)
    end

    return idx
end


function _M.set(tab, ...)
    for i = 1, select('#', ...) do
        tab[i] = select(i, ...)
    end
end


-- only work under lua51 or luajit
function _M.setmt__gc(t, mt)
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() mt.__gc(t) end
    t[prox] = true
    return setmetatable(t, mt)
end


local function deepcopy(orig)
    local orig_type = type(orig)
    if orig_type ~= 'table' then
        return orig
    end

    -- If the array-like table contains nil in the middle,
    -- the len might be smaller than the expected.
    -- But it doesn't affect the correctness.
    local len = #orig
    local copy = new_tab(len, nkeys(orig) - len)
    for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = deepcopy(orig_value)
    end

    return copy
end
_M.deepcopy = deepcopy

local ngx_null = ngx.null
local function merge(origin, extend)
    for k,v in pairs(extend) do
        if type(v) == "table" then
            if type(origin[k] or false) == "table" then
                if _M.nkeys(origin[k]) ~= #origin[k] then
                    merge(origin[k] or {}, extend[k] or {})
                else
                    origin[k] = v
                end
            else
                origin[k] = v
            end
        elseif v == ngx_null then
            origin[k] = nil
        else
            origin[k] = v
        end
    end

    return origin
end
_M.merge = merge


local function patch(node_value, sub_path, conf)
    local sub_value = node_value
    local sub_paths = ngx_re.split(sub_path, "/")
    for i = 1, #sub_paths - 1 do
        local sub_name = sub_paths[i]
        if sub_value[sub_name] == nil then
            sub_value[sub_name] = {}
        end

        sub_value = sub_value[sub_name]

        if type(sub_value) ~= "table" then
            return 400, "invalid sub-path: /"
                      .. _M.concat(sub_paths, 1, i)
        end
    end

    if type(sub_value) ~= "table" then
        return 400, "invalid sub-path: /" .. sub_path
    end

    local sub_name = sub_paths[#sub_paths]
    if sub_name and sub_name ~= "" then
        sub_value[sub_name] = conf
    else
        node_value = conf
    end

    return nil, nil, node_value
end
_M.patch = patch


return _M
