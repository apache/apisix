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

local ws_client = require "resty.websocket.client"
local protoc    = require("protoc")
local pb        = require("pb")

local _M = {}
local mt = { __index = _M }


local pb_state
local function load_proto()
    pb.state(nil)
    protoc.reload()
    pb.option("int64_as_string")
    local pubsub_protoc = protoc.new()
    pubsub_protoc:addpath("apisix/include/apisix/model")
    local ok, err = pcall(pubsub_protoc.loadfile, pubsub_protoc, "pubsub.proto")
    if not ok then
        ngx.log(ngx.ERR, "failed to load protocol: "..err)
        return err
    end
    pb_state = pb.state(nil)
end


local function init_websocket_client(endpoint)
    local ws, err = ws_client:new()
    if not ws then
        ngx.log(ngx.ERR, "failed to create websocket client: "..err)
        return nil, err
    end
    local ok, err = ws:connect(endpoint)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: "..err)
        return nil, err
    end
    return ws
end


function _M.new_ws(server)
    local err = load_proto()
    if err then
        return nil, err
    end
    local ws, err = init_websocket_client(server)
    if not ws then
        return nil, err
    end

    local obj = setmetatable({
        type = "ws",
        ws_client = ws,
    }, mt)

    return obj
end


function _M.send_recv_ws_binary(self, data, is_raw)
    pb.state(pb_state)
    local ws = self.ws_client
    if not is_raw then
        data = pb.encode("PubSubReq", data)
    end
    local _, err = ws:send_binary(data)
    if err then
        return nil, err
    end
    local raw_data, _, err = ws:recv_frame()
    if not raw_data then
        ngx.log(ngx.ERR, "failed to receive the frame: ", err)
        return nil, err
    end
    local data, err = pb.decode("PubSubResp", raw_data)
    if not data then
        ngx.log(ngx.ERR, "failed to decode the frame: ", err)
        return nil, err
    end

    return data
end


function _M.send_recv_ws_text(self, text)
    pb.state(pb_state)
    local ws = self.ws_client
    local _, err = ws:send_text(text)
    if err then
        return nil, err
    end
    local raw_data, _, err = ws:recv_frame()
    if not raw_data then
        ngx.log(ngx.ERR, "failed to receive the frame: ", err)
        return nil, err
    end
    local data, err = pb.decode("PubSubResp", raw_data)
    if not data then
        ngx.log(ngx.ERR, "failed to decode the frame: ", err)
        return nil, err
    end

    return data
end


function _M.close_ws(self)
    self.ws_client:send_close()
end


return _M
