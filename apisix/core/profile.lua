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

local _M = {
    version = 0.1,
    profile = os.getenv("APISIX_PROFILE"),
    apisix_home = (ngx and ngx.config.prefix()) or ""
}


function _M.yaml_path(self, file_name)
    local file_path = self.apisix_home  .. "conf/" .. file_name
    if self.profile then
        file_path = file_path .. "-" .. self.profile
    end
    return file_path .. ".yaml"
end


return _M
