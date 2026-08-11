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
local http = require("resty.http")
local str_match = string.match

local _M = {}


-- follow the redirect to the login page and return the session cookie
-- together with the state bound to it
function _M.begin(port, path)
    local httpc = http.new()
    local uri = "http://127.0.0.1:" .. port .. path

    local res, err = httpc:request_uri(uri, {method = "GET"})
    if not res then
        return nil, nil, err
    end
    if res.status ~= 302 then
        return nil, nil, "expected 302 to the login page, got " .. res.status
    end

    local cookie = res.headers["Set-Cookie"]
    local state = str_match(res.headers["Location"] or "", "state=([0-9a-f]+)")
    if not cookie or not state then
        return nil, nil, "redirect did not carry a session cookie and a state"
    end

    return cookie, state
end


-- drive a full login: pick up the state, then come back with the code
function _M.login(port, path, code, code_query)
    local cookie, state, err = _M.begin(port, path)
    if not cookie then
        return nil, err
    end

    local query = {state = state}
    query[code_query or "code"] = code

    return http.new():request_uri("http://127.0.0.1:" .. port .. path, {
        method = "GET",
        query = query,
        headers = {["Cookie"] = cookie},
    })
end


return _M
