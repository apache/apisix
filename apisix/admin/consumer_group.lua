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
local consumers = require("apisix.consumer").consumers
local resource = require("apisix.admin.resource")
local schema_plugin = require("apisix.admin.plugins").check_schema
local type = type
local tostring = tostring
local ipairs = ipairs


local function check_conf(id, conf, need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local ok, err = schema_plugin(conf.plugins)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


local function delete_checker(id)
    local consumers, consumers_ver = consumers()
    if consumers_ver and consumers then
        for _, consumer in ipairs(consumers) do
            if type(consumer) == "table" and consumer.value
               and consumer.value.group_id
               and tostring(consumer.value.group_id) == id then
                return 400, {error_msg = "can not delete this consumer group,"
                                         .. " consumer [" .. consumer.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    return nil, nil
end


return resource.new({
    name = "consumer_groups",
    kind = "consumer group",
    schema = core.schema.consumer_group,
    checker = check_conf,
    unsupported_methods = {"post"},
    delete_checker = delete_checker
})
