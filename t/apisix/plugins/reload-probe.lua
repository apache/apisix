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

-- A test only plugin recording its lifecycle hooks. Its priority is lower than
-- the one of reload-bad-init, so it is initialized after it: when the reload is
-- aborted this instance has never been initialized and must not be destroyed.
local state = require("lib.reload_probe_state")

local inited = false

local _M = {
    version = 0.1,
    priority = 411,
    name = "reload-probe",
    schema = {type = "object"},
}


function _M.init()
    inited = true
    state.init = state.init + 1
end


function _M.destroy()
    if not inited then
        state.destroy_without_init = state.destroy_without_init + 1
    end

    state.destroy = state.destroy + 1
end


return _M
