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
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
local plugin = require("apisix.plugin")

local math     = math
local pairs    = pairs
local type     = type
local plugin_name = "kafka-logger"
local batch_processor_manager = bp_manager_mod.new("kafka logger")
local ngx = ngx

local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        meta_format = {
            type = "string",
            default = "default",
            enum = {"default", "origin"},
        },
        broker_list = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                [".*"] = {
                    description = "the port of kafka broker",
                    type = "integer",
                    minimum = 1,
                    maximum = 65535,
                },
            },
        },
        kafka_topic = {type = "string"},
        producer_type = {
            type = "string",
            default = "async",
            enum = {"async", "sync"},
        },
        required_acks = {
            type = "integer",
            default = 1,
            enum = { 0, 1, -1 },
        },
        key = {type = "string"},
        timeout = {type = "integer", minimum = 1, default = 3},
        include_req_body = {type = "boolean", default = false},
        include_req_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        -- in lua-resty-kafka, cluster_name is defined as number
        -- see https://github.com/doujiang24/lua-resty-kafka#new-1
        cluster_name = {type = "integer", minimum = 1, default = 1},
    },
    required = {"broker_list", "kafka_topic"}
}

local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}

local _M = {
    version = 0.1,
    priority = 403,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end
    return log_util.check_log_schema(conf)
end


local function get_partition_id(prod, topic, log_message)
    if prod.async then
        local ringbuffer = prod.ringbuffer
        for i = 1, ringbuffer.size, 3 do
            if ringbuffer.queue[i] == topic and
                ringbuffer.queue[i+2] == log_message then
                return math.floor(i / 3)
            end
        end
        core.log.info("current topic in ringbuffer has no message")
        return nil
    end

    -- sync mode
    local sendbuffer = prod.sendbuffer
    if not sendbuffer.topics[topic] then
        core.log.info("current topic in sendbuffer has no message")
        return nil
    end
    for i, message in pairs(sendbuffer.topics[topic]) do
        if log_message == message.queue[2] then
            return i
        end
    end
end


local function create_producer(broker_list, broker_config, cluster_name)
    core.log.info("create new kafka producer instance")
    return producer:new(broker_list, broker_config, cluster_name)
end


local function send_kafka_data(conf, log_message, prod)
    local ok, err = prod:send(conf.kafka_topic, conf.key, log_message)
    core.log.info("partition_id: ",
                  core.log.delay_exec(get_partition_id,
                                      prod, conf.kafka_topic, log_message))

    if not ok then
        return false, "failed to send data to Kafka topic: " .. err ..
                ", brokers: " .. core.json.encode(conf.broker_list)
    end

    return true
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local entry
    if conf.meta_format == "origin" then
        entry = log_util.get_req_original(ctx, conf)
        -- core.log.info("origin entry: ", entry)

    else
        local metadata = plugin.plugin_metadata(plugin_name)
        core.log.info("metadata: ", core.json.delay_encode(metadata))
        if metadata and metadata.value.log_format
          and core.table.nkeys(metadata.value.log_format) > 0
        then
            entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
            core.log.info("custom log format entry: ", core.json.delay_encode(entry))
        else
            entry = log_util.get_full_log(ngx, conf)
            core.log.info("full log entry: ", core.json.delay_encode(entry))
        end
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- reuse producer via lrucache to avoid unbalanced partitions of messages in kafka
    local broker_list = core.table.new(core.table.nkeys(conf.broker_list), 0)
    local broker_config = {}

    for host, port in pairs(conf.broker_list) do
        local broker = {
            host = host,
            port = port
        }
        core.table.insert(broker_list, broker)
    end

    broker_config["request_timeout"] = conf.timeout * 1000
    broker_config["producer_type"] = conf.producer_type
    broker_config["required_acks"] = conf.required_acks

    local prod, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_producer,
                                               broker_list, broker_config, conf.cluster_name)
    core.log.info("kafka cluster name ", conf.cluster_name, ", broker_list[1] port ",
                  prod.client.broker_list[1].port)
    if err then
        return nil, "failed to identify the broker specified: " .. err
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err
        if batch_max_size == 1 then
            data = entries[1]
            if type(data) ~= "string" then
                data, err = core.json.encode(data) -- encode as single {}
            end
        else
            data, err = core.json.encode(entries) -- encode as array [{}]
        end

        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        core.log.info("send data to kafka: ", data)
        return send_kafka_data(conf, data, prod)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
