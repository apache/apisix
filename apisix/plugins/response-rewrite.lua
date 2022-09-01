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
local core        = require("apisix.core")
local expr        = require("resty.expr.v1")
local re_compile  = require("resty.core.regex").re_match_compile
local plugin_name = "response-rewrite"
local ngx         = ngx
local re_match    = ngx.re.match
local re_sub      = ngx.re.sub
local re_gsub     = ngx.re.gsub
local pairs       = pairs
local ipairs      = ipairs
local type        = type
local pcall       = pcall


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        headers = {
            description = "new headers for response",
            anyOf = {
                {
                    type = "object",
                    minProperties = 1,
                    patternProperties = {
                        ["^[^:]+$"] = {
                            oneOf = {
                                {type = "string"},
                                {type = "number"},
                            }
                        }
                    },
                },
                {
                    properties = {
                        add = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string",
                                -- "Set-Cookie: <cookie-name>=<cookie-value>; Max-Age=<number>"
                                pattern = "^[^:]+:[^:]+[^/]$"
                            }
                        },
                        set = {
                            type = "object",
                            minProperties = 1,
                            patternProperties = {
                                ["^[^:]+$"] = {
                                    oneOf = {
                                        {type = "string"},
                                        {type = "number"},
                                    }
                                }
                            },
                        },
                        remove = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string",
                                -- "Set-Cookie"
                                pattern = "^[^:]+$"
                            }
                        },
                    },
                }
            }
        },
        body = {
            description = "new body for response",
            type = "string",
        },
        body_base64 = {
            description = "whether new body for response need base64 decode before return",
            type = "boolean",
            default = false,
        },
        status_code = {
            description = "new status code for response",
            type = "integer",
            minimum = 200,
            maximum = 598,
        },
        vars = {
            type = "array",
        },
        filters = {
            description = "a group of filters that modify response body" ..
                          "by replacing one specified string by another",
            type = "array",
            minItems = 1,
            items = {
                description = "filter that modifies response body",
                type = "object",
                required = {"regex", "replace"},
                properties = {
                    regex = {
                        description = "match pattern on response body",
                        type = "string",
                        minLength = 1,
                    },
                    scope = {
                        description = "regex substitution range",
                        type = "string",
                        enum = {"once", "global"},
                        default = "once",
                    },
                    replace = {
                        description = "regex substitution content",
                        type = "string",
                    },
                    options = {
                        description = "regex options",
                        type = "string",
                        default = "jo",
                    }
                },
            },
        },
    },
    dependencies = {
        body = {
            ["not"] = {required = {"filters"}}
        },
        filters = {
            ["not"] = {required = {"body"}}
        }
    }
}


local _M = {
    version  = 0.1,
    priority = 899,
    name     = plugin_name,
    schema   = schema,
}

local function vars_matched(conf, ctx)
    if not conf.vars then
        return true
    end

    if not conf.response_expr then
        local response_expr, _ = expr.new(conf.vars)
        conf.response_expr = response_expr
    end

    local match_result = conf.response_expr:eval(ctx.var)

    return match_result
end


local function is_new_headers_conf(headers)
    return
        (headers.add and type(headers.add) == "table") or
        (headers.set and type(headers.set) == "table") or
        (headers.remove and type(headers.remove) == "table")
end


local function check_set_headers(headers)
    for field, value in pairs(headers) do
        if type(field) ~= 'string' then
            return false, 'invalid type as header field'
        end

        if type(value) ~= 'string' and type(value) ~= 'number' then
            return false, 'invalid type as header value'
        end

        if #field == 0 then
            return false, 'invalid field length in header'
        end
    end

    return true
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.headers then
        if not is_new_headers_conf(conf.headers) then
            ok, err = check_set_headers(conf.headers)
            if not ok then
                return false, err
            end
        end
    end

    if conf.body_base64 then
        if not conf.body or #conf.body == 0 then
            return false, 'invalid base64 content'
        end
        local body = ngx.decode_base64(conf.body)
        if not body then
            return  false, 'invalid base64 content'
        end
    end

    if conf.vars then
        local ok, err = expr.new(conf.vars)
        if not ok then
            return false, "failed to validate the 'vars' expression: " .. err
        end
    end

    if conf.filters then
        for _, filter in ipairs(conf.filters) do
            local ok, err = pcall(re_compile, filter.regex, filter.options)
            if not ok then
                return false, "regex \"" .. filter.regex ..
                        "\" validation failed: "  .. err
            end
        end
    end

    return true
end


do

function _M.body_filter(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.filters then

        local body = core.response.hold_body_chunk(ctx)
        if not body then
            return
        end

        local err
        for _, filter in ipairs(conf.filters) do
            if filter.scope == "once" then
                body, _, err = re_sub(body, filter.regex, filter.replace, filter.options)
            else
                body, _, err = re_gsub(body, filter.regex, filter.replace, filter.options)
            end
            if err ~= nil then
                core.log.error("regex \"" .. filter.regex .. "\" substitutes failed:" .. err)
            end
        end

        ngx.arg[1] = body
        return
    end

    if conf.body then
        ngx.arg[2] = true
        if conf.body_base64 then
            ngx.arg[1] = ngx.decode_base64(conf.body)
        else
            ngx.arg[1] = conf.body
        end
    end
end


local function create_header_operation(hdr_conf)
    local set = {}
    local add = {}
    if is_new_headers_conf(hdr_conf) then
        if hdr_conf.add then
            for _, value in ipairs(hdr_conf.add) do
                local m, err = re_match(value, [[^([^:\s]+)\s*:\s*([^:]+)$]], "jo")
                if not m then
                    return nil, err
                end
                core.table.insert_tail(add, m[1], m[2])
            end
        end

        if hdr_conf.set then
            for field, value in pairs(hdr_conf.set) do
                --reform header from object into array, so can avoid use pairs, which is NYI
                core.table.insert_tail(set, field, value)
            end
        end

    else
        for field, value in pairs(hdr_conf) do
            core.table.insert_tail(set, field, value)
        end
    end

    return {
        add = add,
        set = set,
        remove = hdr_conf.remove or {},
    }
end


function _M.header_filter(conf, ctx)
    ctx.response_rewrite_matched = vars_matched(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.status_code then
        ngx.status = conf.status_code
    end

    -- if filters have no any match, response body won't be modified.
    if conf.filters or conf.body then
        core.response.clear_header_as_body_modified()
    end

    if not conf.headers then
        return
    end

    local hdr_op, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                 create_header_operation, conf.headers)
    if not hdr_op then
        core.log.error("failed to create header operation: ", err)
        return
    end

    local field_cnt = #hdr_op.add
    for i = 1, field_cnt, 2 do
        local val = core.utils.resolve_var(hdr_op.add[i+1], ctx.var)
        core.response.add_header(hdr_op.add[i], val)
    end

    local field_cnt = #hdr_op.set
    for i = 1, field_cnt, 2 do
        local val = core.utils.resolve_var(hdr_op.set[i+1], ctx.var)
        core.response.set_header(hdr_op.set[i], val)
    end

    local field_cnt = #hdr_op.remove
    for i = 1, field_cnt do
        core.response.set_header(hdr_op.remove[i], nil)
    end
end

end  -- do


return _M
