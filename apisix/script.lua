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
local require    = require
local core       = require("apisix.core")
local loadstring = loadstring
local error      = error


local _M = {}


function _M.load(route, api_ctx)
    local script = route.value.script
    if script == nil or script == "" then
        error("missing valid script")
    end

    local loadfun, err = loadstring(script, "route#" .. route.value.id)
    if not loadfun then
        error("failed to load script: " .. err .. " script: " .. script)
        return nil
    end
    api_ctx.script_obj = loadfun()
end


function _M.run(phase, api_ctx)
    local obj = api_ctx and api_ctx.script_obj
    if not obj then
        core.log.error("missing loaded script object")
        return api_ctx
    end

    core.log.info("loaded script_obj: ", core.json.delay_encode(obj, true))

    local phase_fun = obj[phase]
    if phase_fun then
        phase_fun(api_ctx)
    end

    return api_ctx
end


return _M
