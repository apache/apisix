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
local tab_insert = table.insert
local tab_concat = table.concat
local string_format = string.format
local re_gmatch = ngx.re.gmatch
local re_sub = ngx.re.sub
local ipairs = ipairs
local ngx = ngx

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


function _M.rewrite(conf, ctx)
    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    local ret_code = conf.ret_code
    local uri = conf.uri
    local regex_uri = conf.regex_uri

    if conf.http_to_https and ctx.var.scheme == "http" then
        -- TODO： add test case
        -- PR: https://github.com/apache/apisix/pull/1958
        uri = "https://$host$request_uri"
        local method_name = ngx.req.get_method()
        if method_name == "GET" or method_name == "HEAD" then
            ret_code = 301
        else
         -- https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/308
            ret_code = 308
        end
    end

    if ret_code then
        if uri then
            local new_uri, err = concat_new_uri(uri, ctx)
            if not new_uri then
                core.log.error("failed to generate new uri by: " .. uri .. err)
                return 500
            end

            core.response.set_header("Location", new_uri)
            return ret_code
        elseif regex_uri then
            local new_uri, n, err = re_sub(ctx.var.uri, regex_uri[1],
                                           regex_uri[2], "jo")
            if not new_uri then
                local msg = string_format("failed to substitute the uri:%s (%s) with %s, error:%s",
                                          ctx.var.uri, regex_uri[1], regex_uri[2], err)
                core.log.error(msg)
                return 500
            end

            if n > 0 then
                core.response.set_header("Location", new_uri)
                return ret_code
            end
        end
    end

end


return _M
