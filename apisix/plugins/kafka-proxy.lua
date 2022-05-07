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
        enable_tls = {
            type = "boolean",
            default = false,
        },
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        enable_sasl = {
            type = "boolean",
            default = false,
        },
        sasl_username = {
            type = "string",
            default = "",
        },
        sasl_password = {
            type = "string",
            default = "",
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
    if conf.enable_sasl then
        if not conf.sasl_username or conf.sasl_username == "" then
            return false, "need to set sasl username when enabling kafka sasl authentication"
        end
        if not conf.sasl_password or conf.sasl_password == "" then
            return false, "need to set sasl password when enabling kafka sasl authentication"
        end
    end

    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    ctx.kafka_consumer_enable_tls = conf.enable_tls
    ctx.kafka_consumer_ssl_verify = conf.ssl_verify
    ctx.kafka_consumer_enable_sasl = conf.enable_sasl
    ctx.kafka_consumer_sasl_username = conf.sasl_username
    ctx.kafka_consumer_sasl_password = conf.sasl_password
end


return _M
