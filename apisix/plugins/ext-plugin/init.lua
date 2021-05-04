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
local is_http = ngx.config.subsystem == "http"
local flatbuffers = require("flatbuffers")
local prepare_conf_req = require("A6.PrepareConf.Req")
local prepare_conf_resp = require("A6.PrepareConf.Resp")
local text_entry = require("A6.TextEntry")
local constants = require("apisix.constants")
local core = require("apisix.core")
local helper = require("apisix.plugins.ext-plugin.helper")
local process, ngx_pipe, events
if is_http then
    process = require("ngx.process")
    ngx_pipe = require("ngx.pipe")
    events = require("resty.worker.events")
end
local bit = require("bit")
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local ffi = require("ffi")
local ffi_str = ffi.string
local socket_tcp = ngx.socket.tcp
local str_byte = string.byte
local str_format = string.format
local ngx_timer_at = ngx.timer.at
local exiting = ngx.worker.exiting
local error = error
local events_list


local lrucache = core.lrucache.new({
    type = "plugin",
    ttl = helper.get_conf_token_cache_time(),
})

local schema = {
    type = "object",
    properties = {
        conf = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    name = {
                        type = "string",
                        maxLength = 128,
                        minLength = 1
                    },
                    value = {
                        type = "string",
                    },
                }
            },
            minItems = 1,
        },
        extra_info = {
            type = "array",
            items = {
                type = "string",
                maxLength = 64,
                minLength = 1,
            },
            minItems = 1,
        }
    },
}

local _M = {
    schema = schema,
}
local builder = flatbuffers.Builder(0)


local send
do
    local hdr_buf = ffi.new("unsigned char[4]")
    local buf = core.table.new(2, 0)
    local MAX_DATA_SIZE = lshift(1, 24) - 1

    function send(sock, ty, data)
        hdr_buf[0] = ty

        local len = #data

        core.log.info("sending rpc type: ", ty, " data length: ", len)

        if len > MAX_DATA_SIZE then
            return nil, str_format("the max length of data is %d but got %d", MAX_DATA_SIZE, len)
        end

        -- length is sent as big endian
        for i = 3, 1, -1 do
            hdr_buf[i] = band(len, 255)
            len = rshift(len, 8)
        end

        buf[1] = ffi_str(hdr_buf, 4)
        buf[2] = data
        return sock:send(buf)
    end
end
_M.send = send


local function receive(sock)
    local hdr, err = sock:receive(4)
    if not hdr then
        return nil, err
    end
    if #hdr ~= 4 then
        return nil, "header too short"
    end

    local ty = str_byte(hdr, 1)
    if ty == constants.RPC_ERROR then
        return nil, "TODO: handler err"
    end

    local resp
    local hi, mi, li = str_byte(hdr, 2, 4)
    local len = 256 * (256 * hi + mi) + li

    core.log.info("receiving rpc type: ", ty, " data length: ", len)

    if len > 0 then
        resp, err = sock:receive(len)
        if not resp then
            return nil, err
        end
        if #resp ~= len then
            return nil, "data truncated"
        end
    end

    return ty, resp
end
_M.receive = receive


local rpc_call
local rpc_handlers = {
    nil,
    function (conf, ctx, sock)
        builder:Clear()

        local conf_vec
        if conf.conf then
            local len = #conf.conf
            local textEntries = core.table.new(len, 0)
            for i = 1, len do
                local name = builder:CreateString(conf.conf[i].name)
                local value = builder:CreateString(conf.conf[i].value)
                text_entry.Start(builder)
                text_entry.AddName(builder, name)
                text_entry.AddValue(builder, value)
                local c = text_entry.End(builder)
                textEntries[i] = c
            end
            prepare_conf_req.StartConfVector(builder, len)
            for i = len, 1, -1 do
                builder:PrependUOffsetTRelative(textEntries[i])
            end
            conf_vec = builder:EndVector(len)
        end

        prepare_conf_req.Start(builder)
        if conf_vec then
            prepare_conf_req.AddConf(builder, conf_vec)
        end
        local req = prepare_conf_req.End(builder)
        builder:Finish(req)

        local ok, err = send(sock, constants.RPC_PREPARE_CONF, builder:Output())
        if not ok then
            return nil, "failed to send RPC_PREPARE_CONF: " .. err
        end

        local ty, resp = receive(sock)
        if ty == nil then
            return nil, "failed to receive RPC_PREPARE_CONF: " .. resp
        end

        if ty ~= constants.RPC_PREPARE_CONF then
            return nil, "failed to receive RPC_PREPARE_CONF: unexpected type " .. ty
        end

        local buf = flatbuffers.binaryArray.New(resp)
        local pcr = prepare_conf_resp.GetRootAsResp(buf, 0)
        local token = pcr:ConfToken()

        core.log.notice("get conf token: ", token, " conf: ", core.json.delay_encode(conf.conf))
        return token
    end,
    function (conf, ctx, sock)
        local token, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, rpc_call,
                                                    constants.RPC_PREPARE_CONF, conf, ctx)
        if not token then
            return nil, err
        end

        local req = "hello"
        local ok, err = send(sock, constants.RPC_HTTP_REQ_CALL, req)
        if not ok then
            return nil, "failed to send RPC_HTTP_REQ_CALL: " .. err
        end

        local ty, resp = receive(sock)
        if ty == nil then
            return nil, "failed to receive RPC_HTTP_REQ_CALL: " .. resp
        end

        if ty ~= constants.RPC_HTTP_REQ_CALL then
            return nil, "failed to receive RPC_HTTP_REQ_CALL: unexpected type " .. ty
        end

        core.log.warn(resp)
        return true
    end,
}


rpc_call = function (ty, conf, ctx)
    local path = helper.get_path()

    local sock = socket_tcp()
    sock:settimeouts(1000, 5000, 5000)
    local ok, err = sock:connect(path)
    if not ok then
        return nil, "failed to connect to the unix socket " .. path .. ": " .. err
    end

    local ok, err = rpc_handlers[ty + 1](conf, ctx, sock)
    if not ok then
        sock:close()
        return nil, err
    end

    local ok, err = sock:setkeepalive(180 * 1000, 32)
    if not ok then
        core.log.info("failed to setkeepalive: ", err)
    end
    return true
end


function _M.communicate(conf, ctx)
    local ok, err = rpc_call(constants.RPC_HTTP_REQ_CALL, conf, ctx)
    if not ok then
        core.log.error(err)
        return 503
    end
end


local function create_lrucache()
    if lrucache then
        core.log.warn("flush conf token lrucache")
    end

    lrucache = core.lrucache.new({
        type = "plugin",
        ttl = helper.get_conf_token_cache_time(),
    })
end


local function spawn_proc(cmd)
    local opt = {
        merge_stderr = true,
        environ = {
            "APISIX_CONF_EXPIRE_TIME=" .. helper.get_conf_token_cache_time(),
            "APISIX_LISTEN_ADDRESS=" .. helper.get_path(),
        },
    }
    local proc, err = ngx_pipe.spawn(cmd, opt)
    if not proc then
        error(str_format("failed to start %s: %s", core.json.encode(cmd), err))
        -- TODO: add retry
    end

    proc:set_timeouts(nil, nil, nil, 0)
    return proc
end


local function setup_runner()
    local local_conf = core.config.local_conf()
    local cmd = core.table.try_read_attr(local_conf, "ext-plugin", "cmd")
    if not cmd then
        return
    end

    events_list = events.event_list(
        "process_runner_exit_event",
        "runner_exit"
    )

    -- flush cache when runner exited
    events.register(create_lrucache, events_list._source, events_list.runner_exit)

    -- note that the runner is run under the same user as the Nginx master
    if process.type() ~= "privileged agent" then
        return
    end

    local proc = spawn_proc(cmd)
    ngx_timer_at(0, function(premature)
        if premature then
            return
        end

        while not exiting() do
            while true do
                -- drain output
                local max = 3800 -- smaller than Nginx error log length limit
                local data, err = proc:stdout_read_any(max)
                if not data then
                    if exiting() then
                        return
                    end

                    if err == "closed" then
                        break
                    end
                else
                    -- we log stdout here just for debug or test
                    -- the runner itself should log to a file
                    core.log.warn(data)
                end
            end

            local ok, reason, status = proc:wait()
            if not ok then
                core.log.warn("runner exited with reason: ", reason, ", status: ", status)
            end

            local ok, err = events.post(events_list._source, events_list.runner_exit)
            if not ok then
                core.log.error("post event failure with ", events_list._source, ", error: ", err)
            end

            core.log.warn("respawn runner with cmd: ", core.json.encode(cmd))
            proc = spawn_proc(cmd)
        end
    end)
end


function _M.init_worker()
    create_lrucache()
    setup_runner()
end


return _M
