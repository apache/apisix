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
local core = require("apisix.core")
local state = require("apisix.session_ticket.state")


local _M = {
    uri = "/apisix/admin/plugin_metadata/ssl-session-ticket",
    etcd_key = "/plugin_metadata/ssl-session-ticket",
}


-- a deterministic 80-byte key, its 16-byte name is unique per n
function _M.key(n)
    return string.format("ticket-name-%04d", n) .. string.rep(string.char(65 + n % 26), 64)
end


function _M.b64(n)
    return ngx.encode_base64(_M.key(n))
end


-- base64 of the keys n1, n2, ...
function _M.b64s(...)
    local list = {}
    for i, n in ipairs({...}) do
        list[i] = _M.b64(n)
    end
    return list
end


-- the raw keys n1, n2, ...
function _M.raws(...)
    local list = {}
    for i, n in ipairs({...}) do
        list[i] = _M.key(n)
    end
    return list
end


-- publish a candidate as a producer of the configuration generation of this
-- process does: with a runtime that has one, a candidate without it is stale
function _M.publish(cand)
    if cand.generation == nil then
        cand.generation = state.process_generation()
    end
    return state.publish(cand)
end


-- wait until every worker has started and written its first record, when the
-- runtime has them do so, and until the timers that their init_worker starts
-- at once have run: a test that breaks the dict must not make a late worker
-- fail
function _M.wait_workers(timeout)
    if not state.process_identity(ngx.config.subsystem) then
        return
    end

    local deadline = ngx.now() + (timeout or 5)
    repeat
        local n = 0
        for _, rec in ipairs(state.worker_records() or {}) do
            if rec.subsystem == ngx.config.subsystem then
                n = n + 1
            end
        end
        if n >= ngx.worker.count() then
            ngx.sleep(0.5)
            return
        end
        ngx.sleep(0.1)
        ngx.update_time()
    until ngx.now() > deadline
end


-- the status and the body, without the new line ending it
function _M.req(uri, method, body)
    -- loaded here: it only works in the HTTP subsystem
    local code, msg, res = require("lib.test_admin").test(uri, method, body)
    if code >= 300 then
        res = msg
    end
    if type(res) == "string" then
        res = res:gsub("\n$", "")
    end
    return code, res
end


function _M.put_keys(...)
    -- an array even without any key
    local keys = setmetatable(_M.b64s(...), core.json.array_mt)
    return _M.req(_M.uri, ngx.HTTP_PUT, {keys = keys})
end


-- the stored record and its revision, straight from etcd
function _M.record()
    local res, err = core.etcd.get(_M.etcd_key)
    if not res then
        return nil, err
    end
    if res.status ~= 200 then
        return nil, res.status
    end
    return res.body.node.value, res.body.node.modifiedIndex
end


-- a complete local policy: enabled generated keys, 1h / 19 unless overridden
function _M.policy(over)
    over = over or {}
    local gen = over.generated or {}
    return {
        enabled = over.enabled == nil and true or over.enabled,
        key_source = over.key_source or "generated",
        generated = {
            rotation_interval = gen.rotation_interval or 3600,
            max_keys = gen.max_keys or 19,
        },
    }
end


-- the stored record parsed (keys decrypted) and its revision
function _M.parsed()
    local value, rev = _M.record()
    if not value then
        return nil, rev
    end
    local rec, err = require("apisix.plugins.ssl-session-ticket.record").parse(value)
    if not rec then
        return nil, err
    end
    return rec, rev
end


function _M.delete_record()
    return core.etcd.delete(_M.etcd_key)
end


-- wait until the state satisfies f, returns the last state read
function _M.wait_state(f, timeout)
    local deadline = ngx.now() + (timeout or 5)
    local snap
    repeat
        snap = state.read()
        if snap and f(snap) then
            return snap
        end
        ngx.sleep(0.1)
        ngx.update_time()
    until ngx.now() > deadline
    return snap
end


-- wait until the Control API status satisfies f (by default: no worker lags
-- behind), returns the last status read, decoded
function _M.wait_status(f, timeout)
    f = f or function(st) return st.reason ~= "worker_lag" end
    local deadline = ngx.now() + (timeout or 5)
    local st
    repeat
        local _, body = _M.req("/v1/tls_session_ticket", ngx.HTTP_GET)
        st = require("toolkit.json").decode(body)
        if st and f(st) then
            return st
        end
        ngx.sleep(0.1)
        ngx.update_time()
    until ngx.now() > deadline
    return st
end


-- wait until this node has published the stored record, or the lack of one,
-- and every worker has applied it; returns the status
function _M.wait_applied(timeout)
    local value, rev = _M.record()
    local snap = _M.wait_state(function(s)
        if s.state == "pending" then
            return false
        end
        if value then
            return s.origin ~= nil and s.origin.revision == rev
        end
        return s.origin == nil
    end, timeout)

    return _M.wait_status(function(st)
        return snap and st.version == snap.version and st.reason ~= "worker_lag"
    end, timeout)
end


-- wait until the generator status of this node satisfies f (by default: it
-- has run once and is not in conflict), returns the last status read
function _M.wait_generator(f, timeout)
    f = f or function(st) return st.state ~= "conflict" end
    local deadline = ngx.now() + (timeout or 10)
    local st
    repeat
        st = state.get_status("generator")
        if st and f(st) then
            return st
        end
        ngx.sleep(0.2)
        ngx.update_time()
    until ngx.now() > deadline
    return st
end


-- wait until the stored record satisfies f, returns it and its revision
function _M.wait_record(f, timeout)
    local deadline = ngx.now() + (timeout or 10)
    local value, rev
    repeat
        value, rev = _M.record()
        if f(value, rev) then
            return value, rev
        end
        ngx.sleep(0.2)
        ngx.update_time()
    until ngx.now() > deadline
    return value, rev
end


-- the SSL object of the TLS listeners of the tests
function _M.set_ssl()
    local t = require("lib.test_admin")
    return (t.test("/apisix/admin/ssls/1", ngx.HTTP_PUT, core.json.encode({
        cert = t.read_file("t/certs/apisix.crt"),
        key = t.read_file("t/certs/apisix.key"),
        sni = "test.com",
    })))
end


local ffi
local ticket_ptr, ticket_len


-- what the ticket of a client session is: nil without any, "stateful" for
-- the session id that TLSv1.3 sends when the stateless tickets are off, or
-- the name of the key that encrypted it; and the ticket itself
local function ticket_of(sess)
    if not ffi then
        ffi = require("ffi")
        pcall(ffi.cdef, [[
            int SSL_SESSION_has_ticket(const void *s);
            void SSL_SESSION_get0_ticket(const void *s, const unsigned char **tick,
                                         size_t *len);
        ]])
        ticket_ptr = ffi.new("const unsigned char *[1]")
        ticket_len = ffi.new("size_t[1]")
    end

    if sess == nil or ffi.C.SSL_SESSION_has_ticket(sess) == 0 then
        return nil
    end

    ffi.C.SSL_SESSION_get0_ticket(sess, ticket_ptr, ticket_len)
    local bytes = ffi.string(ticket_ptr[0], tonumber(ticket_len[0]))
    -- key name, IV, encrypted session and HMAC: well above 64 bytes
    if #bytes <= 64 then
        return "stateful", bytes
    end

    return bytes:sub(1, 16), bytes
end


-- the name of the key n, as connect() reports the key of a ticket
function _M.name(n)
    return _M.key(n):sub(1, 16)
end


-- Completes a TLS handshake with the listener on the port, offering
-- opts.session to resume, and reads what the server reports about the
-- connection: "<$ssl_session_reused> <$ssl_protocol> <stateless tickets>".
-- The HTTPS listener answers GET /reused (opts.http), the Stream one a line.
-- Returns {reused, protocol, tickets, ticket, ticket_bytes, session}, or nil
-- and the error. The client protocol is the lua_ssl_protocols of the caller.
function _M.connect(port, opts)
    opts = opts or {}
    local sock = ngx.socket.tcp()
    sock:settimeout(5000)

    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        return nil, "connect: " .. err
    end

    ok, err = sock:sslhandshake(opts.session, "test.com", false)
    if not ok then
        sock:close()
        return nil, "handshake: " .. err
    end

    ok, err = sock:send(opts.http and "GET /reused HTTP/1.0\r\nHost: test.com\r\n\r\n" or "\n")
    if not ok then
        sock:close()
        return nil, "send: " .. err
    end

    local data
    data, err = sock:receive("*a")
    if not data then
        sock:close()
        return nil, "receive: " .. err
    end

    local reused, protocol, tickets = data:match("(%S+) (%S+) (%S+)\n$")
    if not reused then
        sock:close()
        return nil, "unexpected response: " .. data
    end

    -- the session after the response: TLSv1.3 sends its tickets late
    local session = sock:getsslsession()
    sock:close()

    local name, bytes = ticket_of(session)
    return {
        reused = reused == "r",
        protocol = protocol,
        tickets = tickets,
        ticket = name,
        ticket_bytes = bytes,
        session = session,
    }
end


-- the handshakes held in the ClientHello phase, see client_hello_hook()
_M.held = 0
local holding = false


-- hold the next handshakes in the ClientHello phase, or release them
function _M.hold(on)
    holding = on
end


-- for the ClientHello phase of an HTTPS listener, before APISIX's own
function _M.client_hello_hook()
    if not holding then
        return
    end

    _M.held = _M.held + 1
    while holding do
        ngx.sleep(0.01)
    end
    _M.held = _M.held - 1
end


-- wait until a handshake is held
function _M.wait_held()
    for _ = 1, 500 do
        if _M.held > 0 then
            return true
        end
        ngx.sleep(0.01)
    end
    return false
end


-- for the TLS servers of the tests: what connect() reads
function _M.respond()
    local on, err = require("resty.apisix.ssl_session_ticket").connection_tickets()
    ngx.say(ngx.var.ssl_session_reused, " ", ngx.var.ssl_protocol, " ",
            on == nil and err or (on and "on" or "off"))
end


-- whether s contains any of the base64 or raw keys n1, n2, ...
function _M.leaks(s, ...)
    if type(s) ~= "string" then
        s = core.json.encode(s)
    end
    for _, n in ipairs({...}) do
        if core.string.find(s, _M.b64(n)) or core.string.find(s, _M.key(n)) then
            return true
        end
    end
    return false
end


return _M
