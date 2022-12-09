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
local plugin = require("apisix.plugin")
local inspect = require("apisix.inspect")


local plugin_name = "inspect"


local schema = {
    type = "object",
    properties = {},
}


local _M = {
    version = 0.1,
    priority = 200,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end


function _M.init()
    local attr = plugin.plugin_attr(plugin_name)
    local delay
    local hooks_file
    if attr then
        delay = attr.delay
        hooks_file = attr.hooks_file
    end
    core.log.info("delay=", delay, ", hooks_file=", hooks_file)
    return inspect.init(delay, hooks_file)
end


function _M.destroy()
    return inspect.destroy()
end

return _M
