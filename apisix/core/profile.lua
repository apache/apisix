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

--- Profile module.
--
-- @module core.profile

local _M = {
    version = 0.1,
    profile = os.getenv("APISIX_PROFILE") or "",
    apisix_home = (ngx and ngx.config.prefix()) or ""
}

---
--  Get yaml file path by filename under the `conf/`.
--
-- @function core.profile.yaml_path
-- @tparam self self The profile module itself.
-- @tparam string file_name Name of the yaml file to search.
-- @treturn string The path of yaml file searched.
-- @usage
-- local profile = require("apisix.core.profile")
-- ......
-- -- set the working directory of APISIX
-- profile.apisix_home = env.apisix_home .. "/"
-- local local_conf_path = profile:yaml_path("config")
function _M.yaml_path(self, file_name)
    local file_path = self.apisix_home  .. "conf/" .. file_name
    if self.profile ~= "" and file_name ~= "config-default" then
        file_path = file_path .. "-" .. self.profile
    end

    return file_path .. ".yaml"
end


return _M
