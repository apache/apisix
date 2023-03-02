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

local log          = require("apisix.core.log")
local ws_server    = require("resty.websocket.server")
local protoc       = require("protoc")
local pb           = require("pb")
local ngx          = ngx
local setmetatable = setmetatable
local pcall        = pcall


local _M = { version = 0.1 }
local mt = { __index = _M }

local pb_state
local function init_pb_state()
    -- clear current pb state
    local old_pb_state = pb.state(nil)

    -- set int64 rule for pubsub module
    pb.option("int64_as_string")

    -- initialize protoc compiler
    protoc.reload()
    local pubsub_protoc = protoc.new()
    pubsub_protoc:addpath(ngx.config.prefix() .. "apisix/include/apisix/model")
    local ok, err = pcall(pubsub_protoc.loadfile, pubsub_protoc, "pubsub.proto")
    if not ok then
        pubsub_protoc:reset()
        pb.state(old_pb_state)
        return "failed to load pubsub protocol: " .. err
    end

    pb_state = pb.state(old_pb_state)
end


-- parse command name and parameters from client message
local function get_cmd(data)
    -- There are sequence and command properties in the data,
    -- select the handler according to the command value.
    local key = data.req
    return key, data[key]
end


-- send generic response to client
local function send_resp(ws, sequence, data)
    data.sequence = sequence
    local ok, encoded = pcall(pb.encode, "PubSubResp", data)
    if not ok or not encoded then
        log.error("failed to encode response message, err: ", encoded)
        return
    end

    local _, err = ws:send_binary(encoded)
    if err then
        log.error("failed to send response to client, err: ", err)
    end
end


-- send error response to client
local function send_error(ws, sequence, err_msg)
    return send_resp(ws, sequence, {
        error_resp = {
            code = 0,
            message = err_msg,
        },
    })
end


---
-- Create pubsub module instance
--
-- @function core.pubsub.new
-- @treturn pubsub module instance
-- @treturn string|nil error message if present
-- @usage
-- local pubsub, err = core.pubsub.new()
function _M.new()
    if not pb_state then
        local err = init_pb_state()
        if err then
            return nil, err
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

    -- add default ping handler
    obj:on("cmd_ping", function (params)
        return { pong_resp = params }
    end)

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
-- @tparam string command The command to add callback.
-- @tparam func handler The callback function on receipt of command.
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
-- @usage
-- local err = pubsub:wait()
function _M.wait(self)
    local fatal_err
    local ws = self.ws_server
    while true do
        -- read raw data frames from websocket connection
        local raw_data, raw_type, err = ws:recv_frame()
        if err then
            -- terminate the event loop when a fatal error occurs
            if ws.fatal then
                fatal_err = err
                break
            end

            -- skip this loop for non-fatal errors
            log.error("failed to receive websocket frame: ", err)
            goto continue
        end

        -- handle client close connection
        if raw_type == "close" then
            break
        end

        -- the pubsub messages use binary, if the message is not
        -- binary, skip this message
        if raw_type ~= "binary" then
            log.warn("pubsub server receive non-binary data, type: ",
                raw_type, ", data: ", raw_data)
            goto continue
        end

        -- recovery of stored pb_store
        pb.state(pb_state)

        local data, err = pb.decode("PubSubReq", raw_data)
        if not data then
            log.error("pubsub server receives undecodable data, err: ", err)
            send_error(ws, 0, "wrong command")
            goto continue
        end

        -- command sequence code
        local sequence = data.sequence

        local cmd, params = get_cmd(data)
        if not cmd and not params then
            log.warn("pubsub server receives empty command")
            goto continue
        end

        -- find the handler for the current command
        local handler = self.cmd_handler[cmd]
        if not handler then
            log.error("pubsub callback handler not registered for the",
                " command, command: ", cmd)
            send_error(ws, sequence, "unknown command")
            goto continue
        end

        -- call command handler to generate response data
        local resp, err = handler(params)
        if not resp then
            send_error(ws, sequence, err)
            goto continue
        end
        send_resp(ws, sequence, resp)

        ::continue::
    end

    if fatal_err then
        log.error("fatal error in pubsub websocket server, err: ", fatal_err)
    end
    ws:send_close()
end


return _M
