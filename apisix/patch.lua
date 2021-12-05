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
local require = require
require("resty.dns.resolver") -- preload dns resolver to prevent recursive patch
local ipmatcher = require("resty.ipmatcher")
local socket = require("socket")
local unix_socket = require("socket.unix")
local ssl = require("ssl")
local ngx = ngx
local get_phase = ngx.get_phase
local ngx_socket = ngx.socket
local original_tcp = ngx.socket.tcp
local original_udp = ngx.socket.udp
local concat_tab = table.concat
local debug = debug
local new_tab = require("table.new")
local log = ngx.log
local WARN = ngx.WARN
local ipairs = ipairs
local select = select
local setmetatable = setmetatable
local string = string
local table = table
local type = type
local tonumber = tonumber
local tostring = tostring


local config_local
local _M = {}


local function get_local_conf()
    if not config_local then
        config_local = require("apisix.core.config_local")
    end

    return config_local.local_conf()
end


local patch_tcp_socket
do
    local old_tcp_sock_connect

    local function new_tcp_sock_connect(sock, host, port, opts)
        local core_str = require("apisix.core.string")
        local resolver = require("apisix.core.resolver")

        if host then
            if core_str.has_prefix(host, "unix:") then
                if not opts then
                    -- workaround for https://github.com/openresty/lua-nginx-module/issues/860
                    return old_tcp_sock_connect(sock, host)
                end

            elseif not ipmatcher.parse_ipv4(host) and not ipmatcher.parse_ipv6(host) then
                local err
                host, err = resolver.parse_domain(host)
                if not host then
                    return nil, "failed to parse domain: " .. err
                end
            end
        end

        return old_tcp_sock_connect(sock, host, port, opts)
    end


    function patch_tcp_socket(sock)
        if not old_tcp_sock_connect then
            old_tcp_sock_connect = sock.connect
        end

        sock.connect = new_tcp_sock_connect
        return sock
    end
end


do -- `_G.math.randomseed` patch

    -- Seeds the random generator, use with care.
    -- Once - properly - seeded, this method is replaced with a stub
    -- one. This is to enforce best-practices for seeding in ngx_lua,
    -- and prevents third-party modules from overriding our correct seed
    -- (many modules make a wrong usage of `math.randomseed()` by calling
    -- it multiple times or by not using unique seeds for Nginx workers).
    -- Inspired by kong.globalpatches
    local resty_random = require("resty.random")
    local math_randomseed = math.randomseed
    local seeded = {}

    math.randomseed = function()
        local seed
        local worker_pid = ngx.worker.pid()

        -- check seed mark
        if seeded[worker_pid] then
            log(ngx.DEBUG, debug.traceback("attempt to seed already seeded random number " ..
                                           "generator on process #" .. tostring(worker_pid), 2))
            return
        end

        -- get randomseed
        local bytes = resty_random.bytes(8)
        if bytes then
            log(ngx.DEBUG, "seeding from resty.random.bytes")

            local t = {}
            for i = 1, #bytes do
                t[i] = string.byte(bytes, i)
            end

            local str = table.concat(t)
            if #str > 12 then
                -- truncate the final number to prevent integer overflow,
                -- since math.randomseed() could get cast to a platform-specific
                -- integer with a different size and get truncated, hence, lose
                -- randomness.
                -- double-precision floating point should be able to represent numbers
                -- without rounding with up to 15/16 digits but let's use 12 of them.
                str = string.sub(str, 1, 12)
            end
            seed = tonumber(str)
        else
            log(ngx.ERR, "could not seed from resty.random.bytes, seeding ",
                         "seeding with time and process id instead (this can ",
                         "result to duplicated seeds)")

            seed = ngx.now() * 1000 + worker_pid
        end

        seeded[worker_pid] = true
        math_randomseed(seed)
    end
end -- do


local patch_udp_socket
do
    local old_udp_sock_setpeername

    local function new_udp_sock_setpeername(sock, host, port)
        local core_str = require("apisix.core.string")
        local resolver = require("apisix.core.resolver")

        if host then
            if core_str.has_prefix(host, "unix:") then
                return old_udp_sock_setpeername(sock, host)
            end

            if not ipmatcher.parse_ipv4(host) and not ipmatcher.parse_ipv6(host) then
                local err
                host, err = resolver.parse_domain(host)
                if not host then
                    return nil, "failed to parse domain: " .. err
                end
            end
        end

        return old_udp_sock_setpeername(sock, host, port)
    end


    function patch_udp_socket(sock)
        if not old_udp_sock_setpeername then
            old_udp_sock_setpeername = sock.setpeername
        end

        sock.setpeername = new_udp_sock_setpeername
        return sock
    end
end


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

    tlshandshake = function (self, options)
        local reused_session = options.reused_session
        local server_name = options.server_name
        local verify = options.verify
        local send_status_req = options.ocsp_status_req

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
            certificate = options.client_cert_path,
            key = options.client_priv_key_path,
            options = {
                "all",
                "no_sslv2",
                "no_sslv3",
                "no_tlsv1"
            }
        }

        local local_conf, err = get_local_conf()
        if not local_conf then
            return nil, err
        end

        local apisix_ssl = local_conf.apisix.ssl
        if apisix_ssl and apisix_ssl.ssl_trusted_certificate then
            params.cafile = apisix_ssl.ssl_trusted_certificate
        end

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
    end,

    sslhandshake = function (self, reused_session, server_name, verify, send_status_req)
        return self:tlshandshake({
            reused_session = reused_session,
            server_name = server_name,
            verify = verify,
            ocsp_status_req = send_status_req,
        })
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
            return patch_tcp_socket(original_tcp())
        end

        return luasocket_tcp()
    end

    ngx_socket.udp = function ()
        return patch_udp_socket(original_udp())
    end
end


return _M
