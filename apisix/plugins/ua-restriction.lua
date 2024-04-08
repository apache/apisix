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
local ipairs = ipairs
local core = require("apisix.core")
local re_compile = require("resty.core.regex").re_match_compile
local stringx = require('pl.stringx')
local type = type
local str_strip = stringx.strip
local re_find = ngx.re.find

local lrucache_allow = core.lrucache.new({ ttl = 300, count = 4096 })
local lrucache_deny = core.lrucache.new({ ttl = 300, count = 4096 })

local schema = {
    type = "object",
    properties = {
        bypass_missing = {
            type = "boolean",
            default = false,
        },
        allowlist = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                minLength = 1,
            }
        },
        denylist = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                minLength = 1,
            }
        },
        message = {
            type = "string",
            minLength = 1,
            maxLength = 1024,
            default = "Not allowed"
        },
    },
    oneOf = {
        {required = {"allowlist"}},
        {required = {"denylist"}}
    }
}

local plugin_name = "ua-restriction"

local _M = {
    version = 0.1,
    priority = 2999,
    name = plugin_name,
    schema = schema,
}

local function check_with_allow_list(user_agents, allowlist)
    local check = function (user_agent)
        user_agent = str_strip(user_agent)

        for _, rule in ipairs(allowlist) do
            if re_find(user_agent, rule, "jo") then
                return true
            end
        end
        return false
    end

    if type(user_agents) == "table" then
        for _, v in ipairs(user_agents) do
            if lrucache_allow(v, allowlist, check, v) then
                return true
            end
        end
        return false
    else
        return lrucache_allow(user_agents, allowlist, check, user_agents)
    end
end


local function check_with_deny_list(user_agents, denylist)
    local check = function (user_agent)
        user_agent = str_strip(user_agent)

        for _, rule in ipairs(denylist) do
            if re_find(user_agent, rule, "jo") then
                return false
            end
        end
        return true
    end

    if type(user_agents) == "table" then
        for _, v in ipairs(user_agents) do
            if lrucache_deny(v, denylist, check, v) then
                return false
            end
        end
        return true
    else
        return lrucache_deny(user_agents, denylist, check, user_agents)
    end
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.allowlist then
        for _, re_rule in ipairs(conf.allowlist) do
            ok, err = re_compile(re_rule, "j")
            if not ok then
                return false, err
            end
        end
    end

    if conf.denylist then
        for _, re_rule in ipairs(conf.denylist) do
            ok, err = re_compile(re_rule, "j")
            if not ok then
                return false, err
            end
        end
    end

    return true
end


function _M.access(conf, ctx)
    -- after core.request.header function changed
    -- we need to get original header value by using core.request.headers
    local user_agent = core.request.headers(ctx)["User-Agent"]

    if not user_agent then
        if conf.bypass_missing then
            return
        else
            return 403, { message = conf.message }
        end
    end

    local is_passed

    if conf.allowlist then
        is_passed = check_with_allow_list(user_agent, conf.allowlist)
    else
        is_passed = check_with_deny_list(user_agent, conf.denylist)
    end

    if not is_passed then
        return 403, { message = conf.message }
    end
end

return _M
