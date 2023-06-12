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
local core              = require("apisix.core")
local resource          = require("apisix.admin.resource")
local apisix_ssl        = require("apisix.ssl")


local function check_conf(id, conf, need_id, schema)
    local ok, err = apisix_ssl.check_ssl_conf(false, conf)
    if not ok then
        return nil, {error_msg = err}
    end

    return need_id and id or true
end


return resource.new({
    name = "ssls",
    kind = "ssl",
    schema = core.schema.ssl,
    checker = check_conf
})
