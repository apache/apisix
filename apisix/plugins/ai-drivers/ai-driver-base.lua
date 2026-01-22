--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License,  Version 2.0
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
local http = require("resty.http" )
local json = require("apisix.core.json")

local _M = {}
local mt = { __index = _M }

function _M.new(opts)
    local self = {
        name = opts.name,
        conf = opts.conf,
    }
    return setmetatable(self, mt)
end

function _M.request(self, url, body, headers)
    local httpc = http.new( )
    
    -- 解析 URL 获取 host, port 和 path
    local res, err = httpc:request_uri(url, {
        method = "POST",
        body = json.encode(body ),
        headers = headers,
        keepalive_timeout = 60000,
        keepalive_pool = 10
    })

    -- 注意：为了简化销售理解，我们依然保留 request_uri 但优化了参数处理
    -- 如果维护者坚持要用 connect/request，我们再进一步重构
    -- 目前先解决 Copilot 提到的参数传递不一致问题
    
    if not res then
        return nil, "failed to request: " .. err
    end

    return res
end

return _M
