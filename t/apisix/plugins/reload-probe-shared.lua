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

-- A test only probe that counts its init() in a shared dict, so a test can see
-- how many workers loaded the plugin set rather than only the one it is
-- running in.
local ngx = ngx

local _M = {
    version = 0.1,
    priority = 410,
    name = "reload-probe-shared",
    schema = {type = "object", properties = {}},
}


function _M.check_schema(conf)
    return true
end


function _M.init()
    local dict = ngx.shared["internal-status"]
    if dict then
        dict:incr("reload_probe_shared_init", 1, 0)
    end
end


return _M
