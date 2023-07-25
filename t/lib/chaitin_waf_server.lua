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
local _M = {}

local function get_socket()
    ngx.flush(true)
    local sock, err = ngx.req.socket(true)
    if not sock then
        ngx.log(ngx.ERR, "failed to get the request socket: " .. tostring(err))
        return nil
    end
    return sock
end

function _M.pass()
    local sock = get_socket()
    sock:send({ string.char(65), string.char(1), string.char(0), string.char(0), string.char(0) })
    sock:send(".")
    sock:send({ string.char(165), string.char(77), string.char(0), string.char(0), string.char(0) })
    sock:send("{\"event_id\":\"1e902e84bf5a4ead8f7760a0fe2c7719\",\"request_hit_whitelist\":false}")

    ngx.exit(200)
end

function _M.reject()
    local sock = get_socket()
    sock:send({ string.char(65), string.char(1), string.char(0), string.char(0), string.char(0) })
    sock:send("?")
    sock:send({ string.char(2), string.char(3), string.char(0), string.char(0), string.char(0) })
    sock:send("403")
    sock:send({ string.char(37), string.char(77), string.char(0), string.char(0), string.char(0) })
    sock:send("{\"event_id\":\"b3c6ce574dc24f09a01f634a39dca83b\",\"request_hit_whitelist\":false}")
    sock:send({ string.char(35), string.char(79), string.char(0), string.char(0), string.char(0) })
    sock:send("Set-Cookie:sl-session=ulgbPfMSuWRNsi/u7Aj9aA==; Domain=; Path=/; Max-Age=86400\n")
    sock:send({ string.char(164), string.char(51), string.char(0), string.char(0), string.char(0) })
    sock:send("<!-- event_id: b3c6ce574dc24f09a01f634a39dca83b -->")

    ngx.exit(200)
end

function _M.timeout()
    ngx.sleep(100)
    _M.pass()
end

return _M
