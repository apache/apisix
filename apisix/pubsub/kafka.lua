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

local core      = require("apisix.core")
local bconsumer = require("resty.kafka.basic-consumer")
local ffi       = require("ffi")
local C         = ffi.C
local tostring  = tostring
local type      = type
local ipairs    = ipairs
local str_sub   = string.sub

ffi.cdef[[
    int64_t atoll(const char *num);
]]


local _M = {}


-- Handles the conversion of 64-bit integers in the lua-protobuf.
--
-- Because of the limitations of luajit, we cannot use native 64-bit
-- numbers, so pb decode converts int64 to a string in #xxx format
-- to avoid loss of precision, by this function, we convert this
-- string to int64 cdata numbers.
local function pb_convert_to_int64(src)
    if type(src) == "string" then
        -- the format is #1234, so there is a small minimum length of 2
        if #src < 2 then
            return 0
        end
        return C.atoll(ffi.cast("char *", src) + 1)
    else
        return src
    end
end


-- Takes over requests of type kafka upstream in the http_access phase.
function _M.access(api_ctx)
    local pubsub, err = core.pubsub.new()
    if not pubsub then
        core.log.error("failed to initialize pubsub module, err: ", err)
        core.response.exit(400)
        return
    end

    local up_nodes = api_ctx.matched_upstream.nodes

    -- kafka client broker-related configuration
    local broker_list = {}
    for i, node in ipairs(up_nodes) do
        broker_list[i] = {
            host = node.host,
            port = node.port,
        }

        if api_ctx.kafka_consumer_enable_sasl then
            broker_list[i].sasl_config = {
                mechanism = "PLAIN",
                user = api_ctx.kafka_consumer_sasl_username,
                password = api_ctx.kafka_consumer_sasl_password,
            }
        end
    end

    local client_config = {refresh_interval = 30 * 60 * 1000}
    if api_ctx.matched_upstream.tls then
        client_config.ssl = true
        client_config.ssl_verify = api_ctx.matched_upstream.tls.verify
    end

    -- load and create the consumer instance when it is determined
    -- that the websocket connection was created successfully
    local consumer = bconsumer:new(broker_list, client_config)

    pubsub:on("cmd_kafka_list_offset", function (params)
        -- The timestamp parameter uses a 64-bit integer, which is difficult
        -- for luajit to handle well, so the int64_as_string option in
        -- lua-protobuf is used here. Smaller numbers will be decoded as
        -- lua number, while overly larger numbers will be decoded as strings
        -- in the format #number, where the # symbol at the beginning of the
        -- string will be removed and converted to int64_t with the atoll function.
        local timestamp = pb_convert_to_int64(params.timestamp)

        local offset, err = consumer:list_offset(params.topic, params.partition, timestamp)

        if not offset then
            return nil, "failed to list offset, topic: " .. params.topic ..
                ", partition: " .. params.partition .. ", err: " .. err
        end

        offset = tostring(offset)
        return {
            kafka_list_offset_resp = {
                offset = str_sub(offset, 1, #offset - 2)
            }
        }
    end)

    pubsub:on("cmd_kafka_fetch", function (params)
        local offset = pb_convert_to_int64(params.offset)

        local ret, err = consumer:fetch(params.topic, params.partition, offset)
        if not ret then
            return nil, "failed to fetch message, topic: " .. params.topic ..
                ", partition: " .. params.partition .. ", err: " .. err
        end

        -- split into multiple messages when the amount of data in
        -- a single batch is too large
        local messages = ret.records

        -- special handling of int64 for luajit compatibility
        for _, message in ipairs(messages) do
            local timestamp = tostring(message.timestamp)
            message.timestamp = str_sub(timestamp, 1, #timestamp - 2)
            local offset = tostring(message.offset)
            message.offset = str_sub(offset, 1, #offset - 2)
        end

        return {
            kafka_fetch_resp = {
                messages = messages,
            },
        }
    end)

    -- start processing client commands
    pubsub:wait()
end


return _M
