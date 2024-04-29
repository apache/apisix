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
local core = require("apisix.core")
local new_tab = require ("table.new")

local ngx  = ngx
local table_insert = table.insert
local table_concat = table.concat
local ngx_re_gmatch = ngx.re.gmatch


local _M = {}


function _M.remove_specified_cookie(src, key)
    local cookie_key_pattern = "([a-zA-Z0-9-_]*)"
    local cookie_val_pattern = "([a-zA-Z0-9-._]*)"
    local t = new_tab(1, 0)

    local it, err = ngx_re_gmatch(src, cookie_key_pattern .. "=" .. cookie_val_pattern, "jo")
    if not it then
        core.log.error("match origins failed: ", err)
        return src
    end
    while true do
        local m, err = it()
        if err then
            core.log.error("iterate origins failed: ", err)
            return src
        end
        if not m then
            break
        end
        if m[1] ~= key then
            table_insert(t, m[0])
        end
    end

    return table_concat(t, "; ")
end


return _M
