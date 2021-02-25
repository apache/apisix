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
local log = require("apisix.core.log")
local json = require("apisix.core.json")
local table = require("apisix.core.table")
local math_random = math.random
local package_loaded = package.loaded
local setmetatable = setmetatable


local _M = {
    RETURN_RANDOM = 1,
    RETURN_ALL = 2,
}


function _M.resolve(self, domain, selector)
    local client = self.client

    -- this function will dereference the CNAME records
    local answers, err = client.resolve(domain)
    if not answers then
        return nil, "failed to query the DNS server: " .. err
    end

    if answers.errcode then
        return nil, "server returned error code: " .. answers.errcode
                    .. ": " .. answers.errstr
    end

    if selector == _M.RETURN_ALL then
        log.info("dns resolve ", domain, ", result: ", json.delay_encode(answers))
        return table.deepcopy(answers)
    end

    local idx = math_random(1, #answers)
    local answer = answers[idx]
    local dns_type = answer.type
    if dns_type == client.TYPE_A or dns_type == client.TYPE_AAAA then
        log.info("dns resolve ", domain, ", result: ", json.delay_encode(answer))
        return table.deepcopy(answer)
    end

    return nil, "unsupport DNS answer"
end


function _M.new(opts)
    opts.ipv6 = true
    opts.timeout = 2000 -- 2 sec
    opts.retrans = 5 -- 5 retransmissions on receive timeout

    -- make sure each client has its separate room
    package_loaded["resty.dns.client"] = nil
    local dns_client_mod = require("resty.dns.client")

    local ok, err = dns_client_mod.init(opts)
    if not ok then
        return nil, "failed to init the dns client: " .. err
    end

    return setmetatable({client = dns_client_mod}, {__index = _M})
end


return _M
