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
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local tab_insert = table.insert
local tab_concat = table.concat
local string_format = string.format
local re_gmatch = ngx.re.gmatch
local re_sub = ngx.re.sub
local ipairs = ipairs
local ngx = ngx
local str_find = core.string.find
local str_sub  = string.sub
local type = type
local math_random = math.random

local lrucache = core.lrucache.new({
    ttl = 300, count = 100
})


local reg = [[(\\\$[0-9a-zA-Z_]+)|]]         -- \$host
            .. [[\$\{([0-9a-zA-Z_]+)\}|]]    -- ${host}
            .. [[\$([0-9a-zA-Z_]+)|]]        -- $host
            .. [[(\$|[^$\\]+)]]              -- $ or others
local schema = {
    type = "object",
    properties = {
        ret_code = {type = "integer", minimum = 200, default = 302},
        uri = {type = "string", minLength = 2, pattern = reg},
        regex_uri = {
            description = "params for generating new uri that substitute from client uri, " ..
                          "first param is regular expression, the second one is uri template",
            type        = "array",
            maxItems    = 2,
            minItems    = 2,
            items       = {
                description = "regex uri",
                type = "string",
            }
        },
        http_to_https = {type = "boolean"},
        encode_uri = {type = "boolean", default = false},
        append_query_string = {type = "boolean", default = false},
    },
    oneOf = {
        {required = {"uri"}},
        {required = {"regex_uri"}},
        {required = {"http_to_https"}}
    }
}


local plugin_name = "redirect"

local _M = {
    version = 0.1,
    priority = 900,
    name = plugin_name,
    schema = schema,
}


local function parse_uri(uri)
    local iterator, err = re_gmatch(uri, reg, "jiox")
    if not iterator then
        return nil, err
    end

    local t = {}
    while true do
        local m, err = iterator()
        if err then
            return nil, err
        end

        if not m then
            break
        end

        tab_insert(t, m)
    end

    return t
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.regex_uri and #conf.regex_uri > 0 then
        local _, _, err = re_sub("/fake_uri", conf.regex_uri[1],
                                 conf.regex_uri[2], "jo")
        if err then
            local msg = string_format("invalid regex_uri (%s, %s), err:%s",
                                      conf.regex_uri[1], conf.regex_uri[2], err)
            return false, msg
        end
    end

    if conf.http_to_https and conf.append_query_string then
        return false, "only one of `http_to_https` and `append_query_string` can be configured."
    end

    return true
end


    local tmp = {}
local function concat_new_uri(uri, ctx)
    local passed_uri_segs, err = lrucache(uri, nil, parse_uri, uri)
    if not passed_uri_segs then
        return nil, err
    end

    core.table.clear(tmp)

    for _, uri_segs in ipairs(passed_uri_segs) do
        local pat1 = uri_segs[1]    -- \$host
        local pat2 = uri_segs[2]    -- ${host}
        local pat3 = uri_segs[3]    -- $host
        local pat4 = uri_segs[4]    -- $ or others
        core.log.info("parsed uri segs: ", core.json.delay_encode(uri_segs))

        if pat2 or pat3 then
            tab_insert(tmp, ctx.var[pat2 or pat3])
        else
            tab_insert(tmp, pat1 or pat4)
        end
    end

    return tab_concat(tmp, "")
end

local function get_port(attr)
    local port
    if attr then
        port = attr.https_port
    end

    if port then
        return port
    end

    local local_conf = core.config.local_conf()
    local ssl = core.table.try_read_attr(local_conf, "apisix", "ssl")
    if not ssl or not ssl["enable"] then
        return port
    end

    local ports = ssl["listen"]
    if ports and #ports > 0 then
        local idx = math_random(1, #ports)
        port = ports[idx]
        if type(port) == "table" then
            port = port.port
        end
    end

    return port
end

function _M.rewrite(conf, ctx)
    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    local ret_code = conf.ret_code

    local attr = plugin.plugin_attr(plugin_name)
    local ret_port = get_port(attr)

    local uri = conf.uri
    local regex_uri = conf.regex_uri

    local proxy_proto = core.request.header(ctx, "X-Forwarded-Proto")
    local _scheme = proxy_proto or core.request.get_scheme(ctx)
    if conf.http_to_https and _scheme == "http" then
        if ret_port == nil or ret_port == 443 or ret_port <= 0 or ret_port > 65535  then
            uri = "https://$host$request_uri"
        else
            uri = "https://$host:" .. ret_port .. "$request_uri"
        end

        local method_name = ngx.req.get_method()
        if method_name == "GET" or method_name == "HEAD" then
            ret_code = 301
        else
         -- https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/308
            ret_code = 308
        end
    end

    if ret_code then
        local new_uri
        if uri then
            local err
            new_uri, err = concat_new_uri(uri, ctx)
            if not new_uri then
                core.log.error("failed to generate new uri by: " .. uri .. err)
                return 500
            end
        elseif regex_uri then
            local n, err
            new_uri, n, err = re_sub(ctx.var.uri, regex_uri[1],
                                     regex_uri[2], "jo")
            if not new_uri then
                local msg = string_format("failed to substitute the uri:%s (%s) with %s, error:%s",
                                          ctx.var.uri, regex_uri[1], regex_uri[2], err)
                core.log.error(msg)
                return 500
            end

            if n < 1 then
                return
            end
        end

        if not new_uri then
            return
        end

        local index = str_find(new_uri, "?")
        if conf.encode_uri then
            if index then
                new_uri = core.utils.uri_safe_encode(str_sub(new_uri, 1, index-1)) ..
                          str_sub(new_uri, index)
            else
                new_uri = core.utils.uri_safe_encode(new_uri)
            end
        end

        if conf.append_query_string and ctx.var.is_args == "?" then
            if index then
                new_uri = new_uri .. "&" .. (ctx.var.args or "")
            else
                new_uri = new_uri .. "?" .. (ctx.var.args or "")
            end
        end

        core.response.set_header("Location", new_uri)
        return ret_code
    end

end


return _M
