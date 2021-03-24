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
local insert_tab = table.insert
local math_random = math.random
local package_loaded = package.loaded
local ipairs = ipairs
local setmetatable = setmetatable


local _M = {
    RETURN_RANDOM = 1,
    RETURN_ALL = 2,
}


local function gcd(a, b)
    if b == 0 then
        return a
    end

    return gcd(b, a % b)
end


local function resolve_srv(client, answers)
    if #answers == 0 then
        return nil, "empty SRV record"
    end

    local resolved_answers = {}
    local answer_to_count = {}
    for _, answer in ipairs(answers) do
        if answer.type ~= client.TYPE_SRV then
            return nil, "mess SRV with other record"
        end

        local resolved, err = client.resolve(answer.target)
        if not resolved then
            local msg = "failed to resolve SRV record " .. answer.target .. ": " .. err
            return nil, msg
        end

        log.info("dns resolve SRV ", answer.target, ", result: ",
                 json.delay_encode(resolved))

        local weight = answer.weight
        if weight == 0 then
            weight = 1
        end

        local count = #resolved
        answer_to_count[answer] = count
        -- one target may have multiple resolved results
        for _, res in ipairs(resolved) do
            local copy = table.deepcopy(res)
            copy.weight = weight / count
            copy.port = answer.port
            copy.priority = answer.priority
            insert_tab(resolved_answers, copy)
        end
    end

    -- find the least common multiple of the counts
    local lcm = answer_to_count[answers[1]]
    for i = 2, #answers do
        local count = answer_to_count[answers[i]]
        lcm = count * lcm / gcd(count, lcm)
    end
    -- fix the weight as the weight should be integer
    for _, res in ipairs(resolved_answers) do
        res.weight = res.weight * lcm
    end

    return resolved_answers
end


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
        for _, answer in ipairs(answers) do
            if answer.type == client.TYPE_SRV then
                return resolve_srv(client, answers)
            end
        end
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
