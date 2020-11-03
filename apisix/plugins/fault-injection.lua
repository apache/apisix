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

local sleep = core.sleep
local random = math.random

local plugin_name   = "fault-injection"


local schema = {
    type = "object",
    properties = {
        abort = {
            type = "object",
            properties = {
                http_status = {type = "integer", minimum = 200},
                body = {type = "string", minLength = 0},
                percentage = {type = "integer", minimum = 0, maximum = 100}
            },
            minProperties = 1,
        },
        delay = {
            type = "object",
            properties = {
                duration = {type = "number", minimum = 0},
                percentage = {type = "integer", minimum = 0, maximum = 100}
            },
            minProperties = 1,
        }
    },
    minProperties = 1,
}


local _M = {
    version = 0.1,
    priority = 11000,
    name = plugin_name,
    schema = schema,
}


local function sample_hit(percentage)
    if not percentage then
        return true
    end

    return random(0, 100) <= percentage
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.rewrite(conf, ctx)
    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    if conf.delay
       and conf.delay.duration ~= nil
       and sample_hit(conf.delay.percentage)
    then
        sleep(conf.delay.duration)
    end

    if conf.abort
       and conf.abort.http_status ~= nil
       and sample_hit(conf.abort.percentage)
    then
        return conf.abort.http_status, conf.abort.body
    end
end


return _M
