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


local schema = {
    type = "object",
    properties = {
        enable_sasl = {
            type = "boolean",
            default = false,
        },
        sasl = {
            type = "object",
            properties = {
                username = {
                    type = "string",
                    default = "",
                },
                password = {
                    type = "string",
                    default = "",
                },
            },
            required = {"username", "password"},
        },
    },
}


local _M = {
    version = 0.1,
    priority = 508,
    name = "kafka-proxy",
    schema = schema,
}


function _M.check_schema(conf)
    if conf.enable_sasl and not conf.sasl then
        return false, "need to set sasl configuration when enabling kafka sasl authentication"
    end

    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    ctx.kafka_consumer_enable_sasl = conf.enable_sasl
    if conf.enable_sasl then
        ctx.kafka_consumer_sasl_username = conf.sasl.username
        ctx.kafka_consumer_sasl_password = conf.sasl.password
    end
end


return _M
