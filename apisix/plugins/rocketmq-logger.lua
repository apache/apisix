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
local producer = require ("resty.rocketmq.producer")
local acl_rpchook = require("resty.rocketmq.acl_rpchook")
local batch_processor = require("apisix.utils.batch-processor")
local plugin = require("apisix.plugin")

local type     = type
local pairs    = pairs
local plugin_name = "rocketmq-logger"
local stale_timer_running = false
local ngx = ngx
local timer_at = ngx.timer.at
local buffers = {}

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
        nameserver_list = {
            type = "array",
            minItems = 1,
            items = {
                type = "string"
            }
        },
        topic = {type = "string"},
        key = {type = "string"},
        tag = {type = "string"},
        timeout = {type = "integer", minimum = 1, default = 3},
        use_tls = {type = "boolean", default = false},
        access_key = {type = "string", default = ""},
        secret_key = {type = "string", default = ""},
        name = {type = "string", default = "rocketmq logger"},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
        include_req_body = {type = "boolean", default = false},
        include_req_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array",
                items = {
                    type = "string"
                }
            }
        },
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array",
                items = {
                    type = "string"
                }
            }
        },
    },
    required = {"nameserver_list", "topic"}
}

local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}

local _M = {
    version = 0.1,
    priority = 402,
    name = plugin_name,
    schema = schema,
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


-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in pairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, conf: ",
                          core.json.delay_encode(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end


local function create_producer(nameserver_list, producer_config)
    core.log.info("create new rocketmq producer instance")
    local prod = producer.new(nameserver_list, "apisixLogProducer")
    if producer_config.use_tls then
        prod:setUseTLS(true)
    end
    if producer_config.access_key ~= '' then
        local aclHook = acl_rpchook.new(producer_config.access_key, producer_config.secret_key)
        prod:addRPCHook(aclHook)
    end
    prod:setTimeout(producer_config.timeout)
    return prod
end


local function send_rocketmq_data(conf, log_message, prod)
    local result, err = prod:send(conf.topic, log_message, conf.tag, conf.key)
    if not result then
        return false, "failed to send data to rocketmq topic: " .. err ..
                ", nameserver_list: " .. core.json.encode(conf.nameserver_list)
    end

    core.log.info("queue: ", result.sendResult.messageQueue.queueId)

    return true
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local entry
    if conf.meta_format == "origin" then
        entry = log_util.get_req_original(ctx, conf)
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

    if not stale_timer_running then
        -- run the timer every 30 mins if any log is present
        timer_at(1800, remove_stale_objects)
        stale_timer_running = true
    end

    local log_buffer = buffers[conf]
    if log_buffer then
        log_buffer:push(entry)
        return
    end

    -- reuse producer via lrucache to avoid unbalanced partitions of messages in rocketmq
    local producer_config = {
        timeout = conf.timeout * 1000,
        use_tls = conf.use_tls,
        access_key = conf.access_key,
        secret_key = conf.secret_key,
    }

    local prod, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_producer,
            conf.nameserver_list, producer_config)
    if err then
        return nil, "failed to create the rocketmq producer: " .. err
    end
    core.log.info("rocketmq nameserver_list[1] port ",
            prod.client.nameservers[1].port)
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

        core.log.info("send data to rocketmq: ", data)
        return send_rocketmq_data(conf, data, prod)
    end

    local config = {
        name = conf.name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
    }

    local err
    log_buffer, err = batch_processor:new(func, config)

    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end

    buffers[conf] = log_buffer
    log_buffer:push(entry)
end


return _M
