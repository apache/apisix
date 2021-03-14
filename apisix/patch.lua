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
local socket = require("socket")
local unix_socket = require("socket.unix")
local ssl = require("ssl")
local get_phase = ngx.get_phase
local ngx_socket = ngx.socket
local original_tcp = ngx.socket.tcp
local concat_tab = table.concat
local new_tab = require("table.new")
local log = ngx.log
local WARN = ngx.WARN
local ipairs = ipairs
local select = select
local setmetatable = setmetatable
local type = type


local _M = {}


local function flatten(args)
    local buf = new_tab(#args, 0)
    for i, v in ipairs(args) do
        local ty = type(v)
        if ty == "table" then
            buf[i] = flatten(v)
        elseif ty == "boolean" then
            buf[i] = v and "true" or "false"
        elseif ty == "nil" then
            buf[i] = "nil"
        else
            buf[i] = v
        end
    end
    return concat_tab(buf)
end


local luasocket_wrapper = {
    connect = function (self, host, port)
        if not port then
            -- unix socket
            self.sock = unix_socket()
            if self.timeout then
                self.sock:settimeout(self.timeout)
            end

            local path = host:sub(#("unix:") + 1)
            return self.sock:connect(path)
        end

        return self.sock:connect(host, port)
    end,

    send = function(self, ...)
        if select('#', ...) == 1 and type(select(1, ...)) == "string" then
            -- fast path
            return self.sock:send(...)
        end

        -- luasocket's send only accepts a single string
        return self.sock:send(flatten({...}))
    end,

    getreusedtimes = function ()
        return 0
    end,
    setkeepalive = function (self)
        self.sock:close()
        return 1
    end,

    settimeout = function (self, time)
        if time then
            time = time / 1000
        end

        self.timeout = time

        return self.sock:settimeout(time)
    end,
    settimeouts = function (self, connect_time, read_time, write_time)
        connect_time = connect_time or 0
        read_time = read_time or 0
        write_time = write_time or 0

        -- set the max one as the timeout
        local time = connect_time
        if time < read_time then
            time = read_time
        end
        if time < write_time then
            time = write_time
        end

        if time > 0 then
            time = time / 1000
        else
            time = nil
        end

        self.timeout = time

        return self.sock:settimeout(time)
    end,

    sslhandshake = function (self, reused_session, server_name, verify, send_status_req)
        if reused_session then
            log(WARN, "reused_session is not supported yet")
        end

        if send_status_req then
            log(WARN, "send_status_req is not supported yet")
        end

        local params = {
            mode = "client",
            protocol = "any",
            verify = verify and "peer" or "none",
            options = {
                "all",
                "no_sslv2",
                "no_sslv3",
                "no_tlsv1"
            }
        }

        local sec_sock, err = ssl.wrap(self.sock, params)
        if not sec_sock then
            return false, err
        end

        if server_name then
            sec_sock:sni(server_name)
        end

        local success
        success, err = sec_sock:dohandshake()
        if not success then
            return false, err
        end

        self.sock = sec_sock
        return true
    end
}


local mt = {
    __index = function(self, key)
        local sock = self.sock
        local fn = luasocket_wrapper[key]
        if fn then
            self[key] = fn
            return fn
        end

        local origin = sock[key]
        if type(origin) ~= "function" then
            return origin
        end

        fn = function(_, ...)
            return origin(sock, ...)
        end

        self[key] = fn
        return fn
    end
}

local function luasocket_tcp()
    local sock = socket.tcp()
    return setmetatable({sock = sock}, mt)
end


function _M.patch()
    -- make linter happy
    -- luacheck: ignore
    ngx_socket.tcp = function ()
        local phase = get_phase()
        if phase ~= "init" and phase ~= "init_worker" then
            return original_tcp()
        end

        return luasocket_tcp()
    end
end


return _M
