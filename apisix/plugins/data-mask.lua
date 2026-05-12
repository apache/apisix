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
local ngx       = ngx
local ipairs    = ipairs
local next      = next
local type      = type
local re_sub    = ngx.re.sub
local core      = require("apisix.core")
local jp        = require("jsonpath")

local plugin_name = "data-mask"

local schema = {
    type = "object",
    properties = {
        request = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    type = {type = "string", enum = {"query", "header", "body"}},
                    body_format = {type = "string", enum = {"json", "urlencoded"}},
                    name = {type = "string"},
                    action = {type = "string", enum = {"regex", "replace", "remove"}},
                    regex = {type = "string"},
                    value = {type = "string"},
                },
                required = {"type", "name", "action"},
                allOf = {
                    {
                        ["if"] = {
                            properties = {type = {const = "body"}},
                        },
                        ["then"] = {
                            required = {"body_format"},
                        },
                    },
                    {
                        ["if"] = {
                            properties = {action = {const = "regex"}},
                        },
                        ["then"] = {
                            required = {"regex", "value"},
                        },
                    },
                    {
                        ["if"] = {
                            properties = {action = {const = "replace"}},
                        },
                        ["then"] = {
                            required = {"value"},
                        },
                    },
                },
            },
        },
        max_body_size = {
            type = "integer",
            exclusiveMinimum = 0,
            default = 1024 * 1024,
        },
        max_req_post_args = {
            type = "integer",
            default = 100,
            minimum = 0,
        }
    },
}


local _M = {
    version = 0.1,
    priority = 1500,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
         return false, err
    end
    return true
end


local function regex_replace(origin, regex, new)
    local res, _, err = re_sub(origin, regex, new, "jo")
    if not res then
        core.log.error("failed to replace (" .. origin .. ") by regex (".. regex ..
                            ") with new value (" .. new .. "): ", err)
    end
    return res
end


local function mask_table(tab, conf)
    if not tab[conf.name] then
        return false
    end
    local masked = false
    if conf.action == "remove" then
        tab[conf.name] = nil
        masked = true
    elseif conf.action == "replace" then
        tab[conf.name] = conf.value
        masked = true
    elseif conf.action == "regex" then
        local new_arg = regex_replace(tab[conf.name], conf.regex, conf.value)
        if new_arg then
            tab[conf.name] = new_arg
            masked = true
        end
    end
    return masked
end


-- jsonpath index of array starts from 0, lua table index starts from 1
local function table_index(idx)
    if type(idx) == "number" then
        return idx + 1
    end
    return idx
end


local function mask_json(obj, conf)
    -- local nodes = jp.nodes(data, '$..author')
    -- {
    --   { path = {'$', 'store', 'book', 0, 'author'}, value = 'Nigel Rees' },
    --   { path = {'$', 'store', 'book', 1, 'author'}, value = 'Evelyn Waugh' },
    -- }
    local nodes = jp.nodes(obj, conf.name)
    if not nodes then
        return false
    end

    local masked = false
    for _, node in ipairs(nodes) do
        local nested = obj
        -- first element is root($), last element is the field name
        for i = 2, #node.path - 1 do
            nested = nested[table_index(node.path[i])]
        end
        local index = table_index(node.path[#node.path])
        if conf.action == "remove" then
            nested[index] = nil
        elseif conf.action == "replace" then
            nested[index] = conf.value
        elseif conf.action == "regex" then
            nested[index] = regex_replace(node.value, conf.regex, conf.value)
        end
        masked = true
    end
    return masked
end


function _M.log(conf, ctx)
    local args = core.request.get_uri_args(ctx)
    local query_masked = false
    local post_args = {}
    local post_args_masked = false
    local body = ngx.req.get_body_data()
    if body then
        post_args = ngx.req.get_post_args(conf.max_req_post_args)
    end
    local json_body
    local body_masked = false

    if conf.request then
        for _, item in ipairs(conf.request) do
            if item.type == "query" then
                if mask_table(args, item) then
                    query_masked = true
                end
            end

            if item.type == "header" then
                local header = core.request.header(ctx, item.name)
                if header then
                    if item.action == "remove" then
                        core.request.set_header(ctx, item.name, nil)
                    elseif item.action == "replace" then
                        core.request.set_header(ctx, item.name, item.value)
                    elseif item.action == "regex" then
                        core.request.set_header(ctx, item.name,
                                                    regex_replace(header, item.regex, item.value))
                    end
                end
            end

            if item.type == "body" then
                if item.body_format == "urlencoded" then
                    if mask_table(post_args, item) then
                        post_args_masked = true
                    end
                elseif item.body_format == "json" then
                    if body and #body <= conf.max_body_size then
                        if not json_body then
                            local js, err = core.json.decode(body)
                            if not js then
                                core.log.warn("failed to decode json body: ", err)
                            else
                                json_body = js
                            end
                        end
                        if json_body then
                            if mask_json(json_body, item) then
                                body_masked = true
                            end
                        end
                    elseif body and #body > conf.max_body_size then
                        core.log.warn("data-mask: skipping body masking for field '",
                            item.name, "' because body size (", #body,
                            ") exceeds max_body_size (", conf.max_body_size, ")")
                    end

                end
            end
        end
    end

    if query_masked then
        -- for logger plugins
        core.request.set_uri_args(ctx, args)
        if next(args) then
            ctx.var.request_uri = (ctx.var.uri_before_strip or ctx.var.uri)
                                        .. "?" .. core.string.encode_args(args)
        else
            ctx.var.request_uri = (ctx.var.uri_before_strip or ctx.var.uri)
        end
        -- for access log
        ctx.var.request_line = core.request.get_method() .. " " .. ctx.var.request_uri
                                    .. " HTTP/" .. core.request.get_http_version()
        -- TODO: handle upstream_uri in access log when enable proxy-rewrite
    end

    if post_args_masked then
        ngx.req.set_body_data(core.string.encode_args(post_args))
    end

    if body_masked then
        ngx.req.set_body_data(core.json.encode(json_body))
    end
end


return _M
