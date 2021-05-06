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
local ext = require("apisix.plugins.ext-plugin.init")
local constants = require("apisix.constants")
local flatbuffers = require("flatbuffers")
local err_code = require("A6.Err.Code")
local err_resp = require("A6.Err.Resp")
local prepare_conf_req = require("A6.PrepareConf.Req")
local prepare_conf_resp = require("A6.PrepareConf.Resp")


local _M = {}
local builder = flatbuffers.Builder(0)


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
