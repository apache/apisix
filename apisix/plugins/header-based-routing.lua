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
local get_upstreams = require("apisix.upstream").upstreams
local stringx = require('pl.stringx')
local startswith = stringx.startswith
local re_find = ngx.re.find

local lrucache = core.lrucache.new({ ttl = 300, count = 1024 })

local match_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            name = { type = "string" },
            values = {
                type = "array",
                items = { type = "string" }
            },
            mode = {
                enum = { "exact", "prefix", "regex", "exists" },
            }
        },
        required = { "name", "mode" },
    },
}

local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    match = match_schema,
                    upstream_name = { type = "string" },
                },
                required = { "match", "upstream_name" },

                additionalProperties = false
            }
        },
    },
    additionalProperties = false,
}

local plugin_name = "route-by-header"

local _M = {
    version = 0.1,
    priority = 2999,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.rules then
        for _, rule in ipairs(conf.rules) do
            if rule.match then
                for _, match_item in ipairs(rule.match) do
                    if match_item.mode ~= "exists" and not match_item.values then
                        return false, "failed to validate 'match.values'"
                    end
                end
            end
        end
    end
    return true
end

local function is_header_match(match_item, func, req_header_value)
    if match_item.mode == "exists" then
        return req_header_value
    end
    local list = match_item.values or {}
    -- Returns true if func(item) returns true for any item in items.
    for _, v in ipairs(list) do
        if func(v, req_header_value) then
            return true
        end
    end
    return false
end

-- Returns true if func(item) returns true for any item in items.
local function all(list, func, ...)
    for _, v in ipairs(list) do
        if not func(v, ...) then
            return false
        end
    end
    return true
end

local function find(list, func)
    for _, v in ipairs(list) do
        if func(v) then
            return v
        end
    end
    return nil
end

local function get_upstream_id_by_name(upstreams, upstream_name)
    local target_upstream = find(upstreams, function(item)
        return item.value ~= nil and item.value.name == upstream_name
    end)
    if target_upstream ~= nil and target_upstream.value ~= nil then
        return target_upstream.value.id
    end
    return nil
end

local match_funcs = {
    ['exact'] = function(exact_header_value, req_header_value)
        return req_header_value ~= nil and req_header_value == exact_header_value
    end,
    ['prefix'] = function(prefix_header_value, req_header_value)
        return req_header_value ~= nil and startswith(req_header_value, prefix_header_value)
    end,
    ['regex'] = function(regex_header_value, req_header_value)
        return req_header_value ~= nil and re_find(req_header_value, regex_header_value, "jo")
    end,
    ['exists'] = function(_, req_header_value)
        return req_header_value ~= nil
    end,
}

local function rule_match(match_item, ctx)
    local req_header_value = core.request.header(ctx, match_item.name)
    return is_header_match(match_item, match_funcs[match_item.mode], req_header_value)
end

function _M.access(conf, ctx)
    if not conf.rules then
        return
    end
    for _, rule in ipairs(conf.rules) do
        local match = all(rule.match, rule_match, ctx)
        if match then
            local upstreams, upstreams_ver = get_upstreams()
            local upstream_id = lrucache(rule.upstream_name, upstreams_ver, get_upstream_id_by_name,
                    upstreams, rule.upstream_name)
            if upstream_id ~= nil then
                ctx.upstream_id = upstream_id
            end
            return
        end
    end
end

return _M
