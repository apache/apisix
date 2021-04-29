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


local _M = {}


function _M.go()
    local sock = ngx.req.socket()
    local ty, data = ext.receive(sock)
    if not ty then
        ngx.log(ngx.ERR, data)
        return
    end
    ngx.log(ngx.WARN, "receive rpc call successfully")

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
