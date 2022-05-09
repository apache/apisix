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

--- Extensible framework to support publish-and-subscribe scenarios
--
-- @module core.pubsub

local core         = require("apisix.core")
local ws_server    = require("resty.websocket.server")
local protoc       = require("protoc")
local pb           = require("pb")
local setmetatable = setmetatable
local pcall        = pcall
local pairs        = pairs

protoc.reload()
pb.option("int64_as_string")
local pubsub_protoc = protoc.new()


local _M = { version = 0.1 }
local mt = { __index = _M }


---
-- Create pubsub module instance
--
-- @function core.pubsub.new
-- @treturn pubsub module instance
-- @treturn string|nil error message if present
-- @usage
-- local pubsub, err = core.pubsub.new()
function _M.new()
    -- compile the protobuf file on initial load module
    -- ensure that each worker is loaded once
    if not pubsub_protoc.loaded["pubsub.proto"] then
        pubsub_protoc:addpath("apisix")
        local ok, err = pcall(pubsub_protoc.loadfile, pubsub_protoc, "pubsub.proto")
        if not ok then
            pubsub_protoc:reset()
            return nil, "failed to load pubsub protocol: "..err
        end
    end

    local ws, err = ws_server:new()
    if not ws then
        return nil, err
    end

    local obj = setmetatable({
        ws_server = ws,
        cmd_handler = {},
    }, mt)

    return obj
end


---
-- Add command callbacks to pubsub module instances
--
-- The callback function prototype: function (params)
-- The params in the parameters contain the data defined in the requested command.
-- Its first return value is the data, which needs to contain the data needed for
-- the particular resp, returns nil if an error exists.
-- Its second return value is a string type error message, no need to return when
-- no error exists.
--
-- @function core.pubsub.on
-- @usage
-- pubsub:on(command, function (params)
--     return data, err
-- end)
function _M.on(self, command, handler)
    self.cmd_handler[command] = handler
end


---
-- Put the pubsub instance into an event loop, waiting to process client commands
--
-- @function core.pubsub.wait
-- @treturn string|nil error message if present, will terminate the event loop
-- @usage
-- local err = pubsub:wait()
function _M.wait(self)
    local ws = self.ws_server
    while true do
        -- read raw data frames from websocket connection
        local raw_data, raw_type, err = ws:recv_frame()
        if err then
            ws:send_close()
            return "websocket server: "..err
        end

        -- handle client close connection
        if raw_type == "close" then
            ws:send_close()
            return
        end

        -- the pub-sub messages use binary, if the message is not
        -- binary, skip this message
        if raw_type ~= "binary" then
            goto continue
        end

        local data = pb.decode("PubSubReq", raw_data)
        local sequence = data.sequence

        -- call command handler to generate response data
        for key, value in pairs(data) do
            -- There are sequence and command properties in the data,
            -- select the handler according to the command value.
            if key ~= "sequence" then
                local handler = self.cmd_handler[key]
                if not handler then
                    core.log.error("handler not registered for the",
                        " current command, command: ", key)
                    goto continue
                end

                local resp, err = handler(value)
                if not resp then
                    ws:send_binary(pb.encode("PubSubResp", {
                        sequence = sequence,
                        error_resp = {
                            code = 0,
                            message = err,
                        },
                    }))
                    goto continue
                end

                -- write back the sequence
                resp.sequence = sequence
                ws:send_binary(pb.encode("PubSubResp", resp))
            end
        end

        ::continue::
    end
end


return _M
