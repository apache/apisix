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

local ipairs       = ipairs
local core         = require("apisix.core")
local http         = require("resty.http")
local http_client  = require("apisix.utils.http")
local pairs        = pairs
local setmetatable = setmetatable
local type         = type
local tostring     = tostring
local unpack       = unpack
local str_byte     = string.byte
local str_lower    = string.lower

local plugin_name = "forward-auth"

local attr_schema = {
    type = "object",
    properties = {
        http_client = http_client.client_schema,
    },
}

local schema = {
    type = "object",
    properties = {
        uri = {type = "string"},
        allow_degradation = {type = "boolean", default = false},
        status_on_error = {type = "integer", minimum = 200, maximum = 599, default = 403},
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        request_method = {
            type = "string",
            default = "GET",
            enum = {"GET", "POST"},
            description = "the method for client to request the authorization service"
        },
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum request body size in bytes buffered and "
                        .. "forwarded to the authorization service when "
                        .. "request_method is POST"
        },
        request_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "client request header that will be sent to the authorization service"
        },
        extra_headers = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                ["^[^:]+$"] = {
                    type = "string",
                    description = "header value as a string; may contain variables"
                                  .. "like $remote_addr, $request_uri"
                }
            },
            description = "extra headers sent to the authorization service; "
                        .. "values must be strings and can include variables"
                        .. "like $remote_addr, $request_uri."
        },
        upstream_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "authorization response header that will be sent to the upstream"
        },
        client_headers = {
            type = "array",
            default = {},
            items = {type = "string"},
            description = "authorization response header that will be sent to"
                           .. "the client when authorizing failed"
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
    },
    required = {"uri"}
}


local _M = {
    version = 0.1,
    priority = 2002,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local check = {"uri"}
    core.utils.check_https(check, conf, _M.name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, _M.name)

    return core.schema.check(schema, conf)
end


local client_name


-- `plugin_attr.forward-auth.http_client` names the client. Read on first
-- request, because local_conf is not readable while this module is loading.
local function resolve_client_name()
    if client_name then
        return client_name
    end

    local local_conf = core.config.local_conf()
    local attr = core.table.try_read_attr(local_conf, "plugin_attr", plugin_name) or {}

    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("invalid plugin_attr.", plugin_name, ": ", err)
        return nil, "invalid plugin_attr." .. plugin_name .. ": " .. err
    end

    client_name = attr.http_client or http_client.DEFAULT_CLIENT

    return client_name
end


local SLASH = str_byte("/")
local parsed_uris = setmetatable({}, {__mode = "k"})


local function parse_uri(conf)
    local parsed = parsed_uris[conf]
    if parsed then
        return parsed
    end

    local err
    parsed, err = http.parse_uri(nil, conf.uri, false)
    if not parsed then
        return nil, err
    end

    -- a scheme-relative uri takes the scheme of the current request
    if str_byte(conf.uri, 1) ~= SLASH then
        parsed_uris[conf] = parsed
    end

    return parsed
end


-- What resty.http's request_uri does, on the object API both clients share.
local function request_auth(conf, headers, body)
    local name, err = resolve_client_name()
    if not name then
        return nil, err
    end

    local parsed
    parsed, err = parse_uri(conf)
    if not parsed then
        return nil, err
    end

    local httpc
    httpc, err = http_client.new(name)
    if not httpc then
        return nil, err
    end

    httpc:set_timeout(conf.timeout)

    local scheme, host, port, path, query = unpack(parsed)
    local ok
    ok, err = httpc:connect({
        scheme = scheme,
        host = host,
        port = port,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = host,
    })
    if not ok then
        return nil, err
    end

    -- ngx_http_ffi_client announces keep-alive unless the caller sends its own
    -- Connection header; lua-resty-http sends none either way
    if not conf.keepalive and name == http_client.FFI_CLIENT then
        for header in pairs(headers) do
            if str_lower(header) == "connection" then
                headers[header] = nil
            end
        end
        headers["Connection"] = "close"
    end

    local res
    res, err = httpc:request({
        method = conf.request_method,
        path = path,
        query = query,
        headers = headers,
        body = body,
        -- ngx_http_ffi_client reads the whole body in the same resume
        preread_body = true,
    })
    if not res then
        httpc:close()
        return nil, err
    end

    local res_body
    res_body, err = res:read_body()
    if not res_body then
        httpc:close()
        return nil, err
    end

    res.body = res_body

    if conf.keepalive then
        ok, err = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
        if not ok then
            -- e.g. the auth service answered with "Connection: close"
            core.log.info("failed to set keepalive for the auth connection: ", err)
        end
    else
        httpc:close()
    end

    return res
end


function _M.access(conf, ctx)
    local auth_headers = {
        ["X-Forwarded-Proto"] = core.request.get_scheme(ctx),
        ["X-Forwarded-Method"] = core.request.get_method(),
        ["X-Forwarded-Host"] = core.request.get_host(ctx),
        ["X-Forwarded-Uri"] = ctx.var.request_uri,
        ["X-Forwarded-For"] = core.request.get_remote_client_ip(ctx),
    }

    if conf.request_method == "POST" then
        -- body is buffered and re-framed below, so only keep content-encoding.
        -- forwarding client transfer-encoding/content-length/expect would not
        -- match the buffered body.
        auth_headers["Content-Encoding"] = core.request.header(ctx, "content-encoding")
    end

    if conf.extra_headers then
        for header, value in pairs(conf.extra_headers) do
            if type(value) == "number" then
                value = tostring(value)
            end
            local resolve_value, err = core.utils.resolve_var(value, ctx.var)
            if not err then
                auth_headers[header] = resolve_value
            end
            if err then
                core.log.error("failed to resolve variable in extra header '",
                                header, "': ",value,": ",err)
            end
        end
    end

    -- append headers that need to be get from the client request header
    if #conf.request_headers > 0 then
        for _, header in ipairs(conf.request_headers) do
            if not auth_headers[header] then
                auth_headers[header] = core.request.header(ctx, header)
            end
        end
    end

    local body
    if conf.request_method == "POST" then
        local err
        body, err = core.request.get_body(conf.max_req_body_size)
        if err then
            core.log.error("failed to read request body: ", err)
            return 413
        end
    end

    local res, err = request_auth(conf, auth_headers, body)
    if not res and conf.allow_degradation then
        -- drop client-supplied copies of the configured upstream headers
        for _, header in ipairs(conf.upstream_headers) do
            core.request.set_header(ctx, header, nil)
        end
        return
    elseif not res then
        core.log.warn("failed to process forward auth, err: ", err)
        return conf.status_on_error
    end

    if res.status >= 300 then
        local client_headers = {}

        if #conf.client_headers > 0 then
            for _, header in ipairs(conf.client_headers) do
                client_headers[header] = res.headers[header]
            end
        end

        core.response.set_header(client_headers)
        return res.status, res.body
    end

    -- set headers from the auth response, clearing any client-supplied values
    -- for configured headers not present in the auth response
    for _, header in ipairs(conf.upstream_headers) do
        local header_value = res.headers[header]
        -- if header_value is nil, the client header's value will be removed if it exists
        core.request.set_header(ctx, header, header_value)
    end
end


return _M
