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
local require = require

local core = require("apisix.core")
local resource = require("apisix.admin.resource")

local pcall = pcall


local function check_conf(id, conf, need_id, schema, typ)
    local ok, secret_manager = pcall(require, "apisix.secret." .. typ)
    if not ok then
        return false, {error_msg = "invalid secret manager: " .. typ}
    end

    local ok, err = core.schema.check(secret_manager.schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return true
end


return resource.new({
    name = "secrets",
    kind = "secret",
    checker = check_conf,
    unsupported_methods = {"post"}
})
