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
local ipairs    = ipairs
local core      = require("apisix.core")
local lrucache  = core.lrucache.new({
    ttl = 300, count = 512
})


local schema = {
    type = "object",
    properties = {
        message = {
            type = "string",
            minLength = 1,
            maxLength = 1024,
            default = "Your IP address is not allowed"
        },
        whitelist = {
            type = "array",
            items = {anyOf = core.schema.ip_def},
            minItems = 1
        },
        blacklist = {
            type = "array",
            items = {anyOf = core.schema.ip_def},
            minItems = 1
        },
    },
    oneOf = {
        {required = {"whitelist"}},
        {required = {"blacklist"}},
    },
}


local plugin_name = "ip-restriction"


local _M = {
    version = 0.1,
    priority = 3000,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    -- we still need this as it is too complex to filter out all invalid IPv6 via regex
    if conf.whitelist then
        for _, cidr in ipairs(conf.whitelist) do
            if not core.ip.validate_cidr_or_ip(cidr) then
                return false, "invalid ip address: " .. cidr
            end
        end
    end

    if conf.blacklist then
        for _, cidr in ipairs(conf.blacklist) do
            if not core.ip.validate_cidr_or_ip(cidr) then
                return false, "invalid ip address: " .. cidr
            end
        end
    end

    return true
end


function _M.restrict(conf, ctx)
    local block = false
    local remote_addr = ctx.var.remote_addr

    if conf.blacklist then
        local matcher = lrucache(conf.blacklist, nil,
                                 core.ip.create_ip_matcher, conf.blacklist)
        if matcher then
            block = matcher:match(remote_addr)
        end
    end

    if conf.whitelist then
        local matcher = lrucache(conf.whitelist, nil,
                                 core.ip.create_ip_matcher, conf.whitelist)
        if matcher then
            block = not matcher:match(remote_addr)
        end
    end

    if block then
        return 403, { message = conf.message }
    end
end


return _M
