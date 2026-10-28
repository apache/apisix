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
    return _M.req(_M.uri, ngx.HTTP_PUT, {keys = _M.b64s(...)})
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
