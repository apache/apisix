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
local type = type
local core = require("apisix.core")
local table = core.utils.table
local utils = core.utils

local _M = {}


local function patch(node_value, sub_path, conf)
    local sub_value = node_value
    local sub_paths = utils.split_uri(sub_path)
    for i = 1, #sub_paths - 1 do
      local sub_name = sub_paths[i]
      if sub_value[sub_name] == nil then
          sub_value[sub_name] = {}
      end

      sub_value = sub_value[sub_name]

      if type(sub_value) ~= "table" then
          return 400, "invalid sub-path: /"
                      .. table.concat(sub_paths, 1, i)
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
