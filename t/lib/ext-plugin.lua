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
local json = require("toolkit.json")
local ext = require("apisix.plugins.ext-plugin.init")
local constants = require("apisix.constants")
local flatbuffers = require("flatbuffers")
local err_code = require("A6.Err.Code")
local err_resp = require("A6.Err.Resp")
local prepare_conf_req = require("A6.PrepareConf.Req")
local prepare_conf_resp = require("A6.PrepareConf.Resp")
local a6_method = require("A6.Method")
local text_entry = require("A6.TextEntry")
local http_req_call_req = require("A6.HTTPReqCall.Req")
local http_req_call_resp = require("A6.HTTPReqCall.Resp")
local http_req_call_action = require("A6.HTTPReqCall.Action")
local http_req_call_stop = require("A6.HTTPReqCall.Stop")
local http_req_call_rewrite = require("A6.HTTPReqCall.Rewrite")


local _M = {}
local builder = flatbuffers.Builder(0)


local function build_action(action, ty)
    http_req_call_resp.Start(builder)
    http_req_call_resp.AddActionType(builder, ty)
    http_req_call_resp.AddAction(builder, action)
end


function _M.go(case)
    local sock = ngx.req.socket()
    local ty, data = ext.receive(sock)
    if not ty then
        ngx.log(ngx.ERR, data)
        return
    end
    ngx.log(ngx.WARN, "receive rpc call successfully")

    if ty == constants.RPC_PREPARE_CONF then
        if case.inject_error then
            ty = constants.RPC_ERROR
            err_resp.Start(builder)
            err_resp.AddCode(builder, err_code.BAD_REQUEST)
            local req = prepare_conf_req.End(builder)
            builder:Finish(req)
            data = builder:Output()

        else
            local buf = flatbuffers.binaryArray.New(data)
            local pc = prepare_conf_req.GetRootAsReq(buf, 0)

            if case.with_conf then
                local conf = pc:Conf(1)
                assert(conf:Name(), "foo")
                assert(conf:Value(), "bar")
                local conf = pc:Conf(2)
                assert(conf:Name(), "cat")
                assert(conf:Value(), "dog")
            else
                assert(pc:ConfLength() == 0)
            end

            prepare_conf_resp.Start(builder)
            prepare_conf_resp.AddConfToken(builder, 233)
            local req = prepare_conf_req.End(builder)
            builder:Finish(req)
            data = builder:Output()
        end
    end

    if ty == constants.RPC_HTTP_REQ_CALL then
        local buf = flatbuffers.binaryArray.New(data)
        local call_req = http_req_call_req.GetRootAsReq(buf, 0)
        if case.check_input then
            assert(call_req:Id() == 0)
            assert(call_req:ConfToken() == 233)
            assert(call_req:SrcIpLength() == 4)
            assert(call_req:SrcIp(1) == 127)
            assert(call_req:SrcIp(2) == 0)
            assert(call_req:SrcIp(3) == 0)
            assert(call_req:SrcIp(4) == 1)
            assert(call_req:Method() == a6_method.PUT)
            assert(call_req:Path() == "/hello")

            assert(call_req:ArgsLength() == 4)
            local res = {}
            for i = 1, call_req:ArgsLength() do
                local entry = call_req:Args(i)
                local r = res[entry:Name()]
                if r then
                    res[entry:Name()] = {r, entry:Value()}
                else
                    res[entry:Name()] = entry:Value() or true
                end
            end
            assert(json.encode(res) == '{\"xx\":[\"y\",\"z\"],\"y\":\"\",\"z\":true}')

            assert(call_req:HeadersLength() == 5)
            local res = {}
            for i = 1, call_req:HeadersLength() do
                local entry = call_req:Headers(i)
                local r = res[entry:Name()]
                if r then
                    res[entry:Name()] = {r, entry:Value()}
                else
                    res[entry:Name()] = entry:Value() or true
                end
            end
            assert(json.encode(res) == '{\"connection\":\"close\",\"host\":\"localhost\",' ..
                   '\"x-req\":[\"foo\",\"bar\"],\"x-resp\":\"cat\"}')
        elseif case.check_input_ipv6 then
            assert(call_req:SrcIpLength() == 16)
            for i = 1, 15 do
                assert(call_req:SrcIp(i) == 0)
            end
            assert(call_req:SrcIp(16) == 1)
        elseif case.check_input_rewrite_host then
            for i = 1, call_req:HeadersLength() do
                local entry = call_req:Headers(i)
                if entry:Name() == "host" then
                    assert(entry:Value() == "test.com")
                end
            end
        elseif case.check_input_rewrite_path then
            assert(call_req:Path() == "/xxx")
        elseif case.check_input_rewrite_args then
            assert(call_req:Path() == "/xxx")
            assert(call_req:ArgsLength() == 1)
            local entry = call_req:Args(1)
            assert(entry:Name() == "x")
            assert(entry:Value() == "z")
        else
            assert(call_req:Method() == a6_method.GET)
        end

        if case.stop == true then
            local len = 3
            http_req_call_stop.StartBodyVector(builder, len)
            builder:PrependByte(string.byte("t"))
            builder:PrependByte(string.byte("a"))
            builder:PrependByte(string.byte("c"))
            local b = builder:EndVector(len)

            local hdrs = {
                {"X-Resp", "foo"},
                {"X-Req", "bar"},
            }
            local len = #hdrs
            local textEntries = {}
            for i = 1, len do
                local name = builder:CreateString(hdrs[i][1])
                local value = builder:CreateString(hdrs[i][2])
                text_entry.Start(builder)
                text_entry.AddName(builder, name)
                text_entry.AddValue(builder, value)
                local c = text_entry.End(builder)
                textEntries[i] = c
            end
            http_req_call_stop.StartHeadersVector(builder, len)
            for i = len, 1, -1 do
                builder:PrependUOffsetTRelative(textEntries[i])
            end
            local vec = builder:EndVector(len)

            http_req_call_stop.Start(builder)
            http_req_call_stop.AddStatus(builder, 405)
            http_req_call_stop.AddBody(builder, b)
            http_req_call_stop.AddHeaders(builder, vec)
            local action = http_req_call_stop.End(builder)
            build_action(action, http_req_call_action.Stop)

        elseif case.rewrite == true or case.rewrite_host == true then
            local hdrs
            if case.rewrite_host then
                hdrs = {{"host", "127.0.0.1"}}
            else
                hdrs = {
                    {"X-Delete", nil},
                    {"X-Change", "bar"},
                    {"X-Add", "bar"},
                }
            end

            local len = #hdrs
            local textEntries = {}
            for i = 1, len do
                local name = builder:CreateString(hdrs[i][1])
                local value
                if hdrs[i][2] then
                    value = builder:CreateString(hdrs[i][2])
                end
                text_entry.Start(builder)
                text_entry.AddName(builder, name)
                if value then
                    text_entry.AddValue(builder, value)
                end
                local c = text_entry.End(builder)
                textEntries[i] = c
            end
            http_req_call_rewrite.StartHeadersVector(builder, len)
            for i = len, 1, -1 do
                builder:PrependUOffsetTRelative(textEntries[i])
            end
            local vec = builder:EndVector(len)

            local path = builder:CreateString("/uri")

            http_req_call_rewrite.Start(builder)
            http_req_call_rewrite.AddPath(builder, path)
            http_req_call_rewrite.AddHeaders(builder, vec)
            local action = http_req_call_rewrite.End(builder)
            build_action(action, http_req_call_action.Rewrite)

        elseif case.rewrite_args == true or case.rewrite_args_only == true then
            local path = builder:CreateString("/plugin_proxy_rewrite_args")

            local args = {
                {"a", "foo"},
                {"d", nil},
                {"c", "bar"},
                {"a", "bar"},
            }

            local len = #args
            local textEntries = {}
            for i = 1, len do
                local name = builder:CreateString(args[i][1])
                local value
                if args[i][2] then
                    value = builder:CreateString(args[i][2])
                end
                text_entry.Start(builder)
                text_entry.AddName(builder, name)
                if value then
                    text_entry.AddValue(builder, value)
                end
                local c = text_entry.End(builder)
                textEntries[i] = c
            end
            http_req_call_rewrite.StartHeadersVector(builder, len)
            for i = len, 1, -1 do
                builder:PrependUOffsetTRelative(textEntries[i])
            end
            local vec = builder:EndVector(len)

            http_req_call_rewrite.Start(builder)
            if not case.rewrite_args_only then
                http_req_call_rewrite.AddPath(builder, path)
            end
            http_req_call_rewrite.AddArgs(builder, vec)
            local action = http_req_call_rewrite.End(builder)
            build_action(action, http_req_call_action.Rewrite)

        elseif case.rewrite_bad_path == true then
            local path = builder:CreateString("/plugin_proxy_rewrite_args?a=2")
            http_req_call_rewrite.Start(builder)
            http_req_call_rewrite.AddPath(builder, path)
            local action = http_req_call_rewrite.End(builder)
            build_action(action, http_req_call_action.Rewrite)

        else
            http_req_call_resp.Start(builder)
        end

        local req = http_req_call_resp.End(builder)
        builder:Finish(req)
        data = builder:Output()
    end

    local ok, err = ext.send(sock, ty, data)
    if not ok then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, "send rpc call response successfully")
end


function _M.header_too_short()
    local sock = ngx.req.socket()
    local ty, data = ext.receive(sock)
    if not ty then
        ngx.log(ngx.ERR, data)
        return
    end
    ngx.log(ngx.WARN, "receive rpc call successfully")

    local ok, err = sock:send({string.char(2), string.char(1)})
    if not ok then
        ngx.log(ngx.ERR, err)
        return
    end
end


function _M.data_too_short()
    local sock = ngx.req.socket()
    local ty, data = ext.receive(sock)
    if not ty then
        ngx.log(ngx.ERR, data)
        return
    end
    ngx.log(ngx.WARN, "receive rpc call successfully")

    local ok, err = sock:send({string.char(2), string.char(1), string.rep(string.char(0), 3)})
    if not ok then
        ngx.log(ngx.ERR, err)
        return
    end
end


return _M
