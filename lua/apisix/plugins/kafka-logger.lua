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
local core     = require("apisix.core")
local log_util = require("apisix.utils.log-util")
local producer = require ("resty.kafka.producer")
local pairs    = pairs
local type     = type
local table    = table

local plugin_name = "kafka-logger"
local ngx = ngx

local timer_at = ngx.timer.at

local schema = {
    type = "object",
    properties = {
        broker_list = {
            type = "object"
        },
        timeout = {   -- timeout in milliseconds
            type = "integer", minimum = 1, default= 2000
        },
        kafka_topic = {type = "string"},
        async =  {type = "boolean", default = false},
        key = {type = "string"},
        max_retry = {type = "integer", minimum = 0 , default = 3},
    },
    required = {"broker_list", "kafka_topic", "key"}
}

local _M = {
    version = 0.1,
    priority = 403,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function log(premature, conf, log_message)
    if premature then
        return
    end

    if core.table.nkeys(conf.broker_list) == 0 then
        core.log.error("failed to identify the broker specified")
    end

    local broker_list = {}
    local broker_config = {}

    for host, port  in pairs(conf.broker_list) do
        if type(host) == 'string'
                and type(port) == 'number' then

            local broker = {
                host = host, port = port
            }
            table.insert(broker_list,broker)
        end
    end

    broker_config["request_timeout"] = conf.timeout
    broker_config["max_retry"] = conf.max_retry

    --Async producers will queue logs and push them when the buffer exceeds.
    if conf.async then
        broker_config["producer_type"] = "async"
    end

    local prod, err = producer:new(broker_list,broker_config)
    if err then
        core.log.error("failed to identify the broker specified", err)
        return
    end

    local ok, err = prod:send(conf.kafka_topic, conf.key, log_message)
    if not ok then
        core.log.error("failed to send data to Kafka topic", err)
    end
end

function _M.log(conf)
    return timer_at(0, log, conf, core.json.encode(log_util.get_full_log(ngx)))
end

return _M
