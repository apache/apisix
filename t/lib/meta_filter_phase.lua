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
local cjson = require("cjson.safe")
local http = require("resty.http")
local t = require("lib.test_admin")

local _M = {}


-- creates route 1 proxying /fp to the block's upstream_server_config location
function _M.set_route(plugins)
    local code, body = t.test("/apisix/admin/routes/1", ngx.HTTP_PUT, cjson.encode({
        uri = "/fp",
        methods = {"GET", "HEAD", "POST", "OPTIONS"},
        plugins = plugins,
        upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
    }))
    if code >= 300 then
        ngx.say("failed to set route: ", body)
        return ngx.exit(200)
    end
end


function _M.req(query, method, headers)
    local httpc = http.new()
    local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                       .. "/fp" .. (query or ""), {
        method = method or "GET",
        headers = headers,
    })
    if not res then
        ngx.say("failed to request: ", err)
        return ngx.exit(200)
    end
    return res
end


-- prints one "<status> <response body>" line per entry and removes the file
function _M.say_log_entries(path)
    ngx.sleep(0.2)
    local fd = io.open(path, "r")
    if fd then
        for line in fd:lines() do
            local entry = cjson.decode(line)
            ngx.say(entry.response.status, " ", tostring(entry.response.body))
        end
        fd:close()
        os.remove(path)
    end
    ngx.say("end of log")
end


return _M
