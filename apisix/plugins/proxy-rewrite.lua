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
local plugin_name = "proxy-rewrite"
local pairs       = pairs
local ipairs      = ipairs
local ngx         = ngx
local type        = type
local re_sub      = ngx.re.sub
local re_match    = ngx.re.match
local req_set_uri = ngx.req.set_uri
local sub_str     = string.sub
local str_find    = core.string.find

local switch_map = {GET = ngx.HTTP_GET, POST = ngx.HTTP_POST, PUT = ngx.HTTP_PUT,
                    HEAD = ngx.HTTP_HEAD, DELETE = ngx.HTTP_DELETE,
                    OPTIONS = ngx.HTTP_OPTIONS, MKCOL = ngx.HTTP_MKCOL,
                    COPY = ngx.HTTP_COPY, MOVE = ngx.HTTP_MOVE,
                    PROPFIND = ngx.HTTP_PROPFIND, LOCK = ngx.HTTP_LOCK,
                    UNLOCK = ngx.HTTP_UNLOCK, PATCH = ngx.HTTP_PATCH,
                    TRACE = ngx.HTTP_TRACE,
                }
local schema_method_enum = {}
for key in pairs(switch_map) do
    core.table.insert(schema_method_enum, key)
end

local lrucache = core.lrucache.new({
    type = "plugin",
})

core.ctx.register_var("proxy_rewrite_regex_uri_captures", function(ctx)
    return ctx.proxy_rewrite_regex_uri_captures
end)

local schema = {
    type = "object",
    properties = {
        uri = {
            description = "new uri for upstream",
            type        = "string",
            minLength   = 1,
            maxLength   = 4096,
            pattern     = [[^\/.*]],
        },
        method = {
            description = "proxy route method",
            type        = "string",
            enum        = schema_method_enum
        },
        regex_uri = {
            description = "new uri that substitute from client uri " ..
                          "for upstream, lower priority than uri property",
            type        = "array",
            minItems    = 2,
            items       = {
                description = "regex uri",
                type = "string",
            }
        },
        host = {
            description = "new host for upstream",
            type        = "string",
            pattern     = [[^[0-9a-zA-Z-.]+(:\d{1,5})?$]],
        },
        headers = {
            description = "new headers for request",
            oneOf = {
                {
                    type = "object",
                    minProperties = 1,
                    additionalProperties = false,
                    properties = {
                        add = {
                            type = "object",
                            minProperties = 1,
                            patternProperties = {
                                ["^[^:]+$"] = {
                                    oneOf = {
                                        { type = "string" },
                                        { type = "number" }
                                    }
                                }
                            },
                        },
                        set = {
                            type = "object",
                            minProperties = 1,
                            patternProperties = {
                                ["^[^:]+$"] = {
                                    oneOf = {
                                        { type = "string" },
                                        { type = "number" },
                                    }
                                }
                            },
                        },
                        remove = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string",
                                -- "Referer"
                                pattern = "^[^:]+$"
                            }
                        },
                    },
                },
                {
                    type = "object",
                    minProperties = 1,
                    patternProperties = {
                        ["^[^:]+$"] = {
                            oneOf = {
                                { type = "string" },
                                { type = "number" }
                            }
                        }
                    },
                }
            },

        },
        use_real_request_uri_unsafe = {
            description = "use real_request_uri instead, THIS IS VERY UNSAFE.",
            type        = "boolean",
            default     = false,
        },
    },
    minProperties = 1,
}


local _M = {
    version  = 0.1,
    priority = 1008,
    name     = plugin_name,
    schema   = schema,
}

local function is_new_headers_conf(headers)
    return (headers.add and type(headers.add) == "table") or
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

        core.log.info("header field: ", field)
        if not core.utils.validate_header_field(field) then
            return false, 'invalid field character in header'
        end
        if not core.utils.validate_header_value(value) then
            return false, 'invalid value character in header'
        end
    end

    return true
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.regex_uri and #conf.regex_uri > 0 then
        if (#conf.regex_uri % 2 ~= 0) then
            return false, "The length of regex_uri should be an even number"
        end
        for i = 1, #conf.regex_uri, 2 do
            local _, _, err = re_sub("/fake_uri", conf.regex_uri[i],
                conf.regex_uri[i + 1], "jo")
            if err then
                return false, "invalid regex_uri(" .. conf.regex_uri[i] ..
                    ", " .. conf.regex_uri[i + 1] .. "): " .. err
            end
        end
    end

    -- check headers
    if not conf.headers then
        return true
    end

    if conf.headers then
        if not is_new_headers_conf(conf.headers) then
            ok, err = check_set_headers(conf.headers)
            if not ok then
                return false, err
            end
        end
    end

    return true
end


do
    local upstream_vars = {
        host       = "upstream_host",
        upgrade    = "upstream_upgrade",
        connection = "upstream_connection",
    }
    local upstream_names = {}
    for name, _ in pairs(upstream_vars) do
        core.table.insert(upstream_names, name)
    end

    local function create_header_operation(hdr_conf)
        local set = {}
        local add = {}

        if is_new_headers_conf(hdr_conf) then
            if hdr_conf.add then
                for field, value in pairs(hdr_conf.add) do
                    core.table.insert_tail(add, field, value)
                end
            end
            if hdr_conf.set then
                for field, value in pairs(hdr_conf.set) do
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


    local function escape_separator(s)
        return re_sub(s, [[\?]], "%3F", "jo")
    end


function _M.rewrite(conf, ctx)
    for _, name in ipairs(upstream_names) do
        if conf[name] then
            ctx.var[upstream_vars[name]] = conf[name]
        end
    end

    local upstream_uri = ctx.var.uri
    local separator_escaped = false
    if conf.use_real_request_uri_unsafe then
        upstream_uri = ctx.var.real_request_uri
    end

    if conf.uri ~= nil then
        separator_escaped = true
        upstream_uri = core.utils.resolve_var(conf.uri, ctx.var, escape_separator)

    elseif conf.regex_uri ~= nil then
        if not str_find(upstream_uri, "?") then
            separator_escaped = true
        end

        local error_msg
        for i = 1, #conf.regex_uri, 2 do
            local captures, err = re_match(upstream_uri, conf.regex_uri[i], "jo")
            if err then
                error_msg = "failed to match the uri " .. ctx.var.uri ..
                    " (" .. conf.regex_uri[i] .. ") " .. " : " .. err
                break
            end

            if captures then
                ctx.proxy_rewrite_regex_uri_captures = captures

                local uri, _, err = re_sub(upstream_uri,
                    conf.regex_uri[i], conf.regex_uri[i + 1], "jo")
                if uri then
                    upstream_uri = uri
                else
                    error_msg = "failed to substitute the uri " .. ngx.var.uri ..
                        " (" .. conf.regex_uri[i] .. ") with " ..
                        conf.regex_uri[i + 1] .. " : " .. err
                end

                break
            end
        end

        if error_msg ~= nil then
            core.log.error(error_msg)
            return 500, { error_msg = error_msg }
        end
    end

    if not conf.use_real_request_uri_unsafe then
        local index
        if separator_escaped then
            index = str_find(upstream_uri, "?")
        end

        if index then
            upstream_uri = core.utils.uri_safe_encode(sub_str(upstream_uri, 1, index - 1)) ..
                sub_str(upstream_uri, index)
        else
            -- The '?' may come from client request '%3f' when we use ngx.var.uri directly or
            -- via regex_uri
            upstream_uri = core.utils.uri_safe_encode(upstream_uri)
        end

        req_set_uri(upstream_uri)

        if ctx.var.is_args == "?" then
            if index then
                ctx.var.upstream_uri = upstream_uri .. "&" .. (ctx.var.args or "")
            else
                ctx.var.upstream_uri = upstream_uri .. "?" .. (ctx.var.args or "")
            end
        else
            ctx.var.upstream_uri = upstream_uri
        end
    else
        ctx.var.upstream_uri = upstream_uri
    end

    if conf.headers then
        local hdr_op, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                    create_header_operation, conf.headers)
        if not hdr_op then
            core.log.error("failed to create header operation: ", err)
            return
        end

        local field_cnt = #hdr_op.add
        for i = 1, field_cnt, 2 do
            local val = core.utils.resolve_var_with_captures(hdr_op.add[i + 1],
                                            ctx.proxy_rewrite_regex_uri_captures)
            val = core.utils.resolve_var(val, ctx.var)
            -- A nil or empty table value will cause add_header function to throw an error.
            if val then
                local header = hdr_op.add[i]
                core.request.add_header(ctx, header, val)
            end
        end

        local field_cnt = #hdr_op.set
        for i = 1, field_cnt, 2 do
            local val = core.utils.resolve_var_with_captures(hdr_op.set[i + 1],
                                            ctx.proxy_rewrite_regex_uri_captures)
            val = core.utils.resolve_var(val, ctx.var)
            core.request.set_header(ctx, hdr_op.set[i], val)
        end

        local field_cnt = #hdr_op.remove
        for i = 1, field_cnt do
            core.request.set_header(ctx, hdr_op.remove[i], nil)
        end

    end

    if conf.method then
        ngx.req.set_method(switch_map[conf.method])
    end
end

end  -- do


return _M
