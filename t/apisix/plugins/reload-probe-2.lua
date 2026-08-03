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

-- A second lifecycle probe, with a lower priority than reload-probe, so that
-- the two are initialized in a known order and the destroy order can be
-- asserted against it.
local state = require("lib.reload_probe_state")

local plugin_name = "reload-probe-2"
local inited = false

local _M = {
    version = 0.1,
    priority = 410,
    name = plugin_name,
    schema = {type = "object"},
}


function _M.init()
    inited = true
    state.init = state.init + 1
    state.record(plugin_name, "init")
end


function _M.destroy()
    if not inited then
        state.destroy_without_init = state.destroy_without_init + 1
    end

    inited = false
    state.destroy = state.destroy + 1
    state.record(plugin_name, "destroy")
end


return _M
