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
local plugin_checker = require("apisix.plugin").plugin_checker
local error = error


local consumer_groups


local _M = {
}


function _M.init_worker()
    local err
    consumer_groups, err = core.config.new("/consumer_groups", {
        automatic = true,
        item_schema = core.schema.consumer_group,
        checker = plugin_checker,
    })
    if not consumer_groups then
        error("failed to sync /consumer_groups: " .. err)
    end
end


function _M.get(id)
    return consumer_groups:get(id)
end


return _M
