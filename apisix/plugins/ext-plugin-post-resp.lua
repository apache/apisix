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
local ext = require("apisix.plugins.ext-plugin.init")
local constants = require("apisix.constants")
local http = require("resty.http")

local ngx       = ngx
local ngx_print = ngx.print
local ngx_flush = ngx.flush
local pairs     = pairs
local string    = string
local str_sub   = string.sub
local str_lower = string.lower

local name = "ext-plugin-post-resp"
local _M = {
    version = 0.1,
    priority = -4000,
    name = name,
    schema = ext.schema,
}


local exclude_resp_header = {
    -- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
    -- note content-length & apisix-cache-status are not strictly
    -- hop-by-hop but we will be adjusting it here anyhow
    ["connection"]          = true,
    ["keep-alive"]          = true,
    ["proxy-authenticate"]  = true,
    ["proxy-authorization"] = true,
    ["te"]                  = true,
    ["trailers"]            = true,
    ["transfer-encoding"]   = true,
    ["upgrade"]             = true,
    ["content-length"]      = true,
    ["apisix-cache-status"] = true,
    -- https://github.com/nginx/nginx/blob/master/src/http/modules/ngx_http_proxy_module.c#L833
    ["date"]                = true,
    ["server"]              = true,
    ["x-pad"]               = true,
    ["X-Accel-Expires"]     = true,
    ["X-Accel-Redirect"]    = true,
    ["X-Accel-Limit-Rate"]  = true,
    ["X-Accel-Buffering"]   = true,
    ["X-Accel-Charset"]     = true,
}


local function include_req_headers(ctx)
    -- TODO: handle proxy_set_header
    return core.request.headers(ctx)
end


local function get_response(ctx)
    local httpc = http.new()
    local ok, err = httpc:connect({
        scheme = ctx.upstream_scheme,
        host = ctx.picked_server.host,
        port = ctx.picked_server.port,
    })

    if not ok then
        return nil, err
    end
    -- TODO: set timeout
    local uri, args
    if ctx.var.upstream_uri == "" then
        -- use original uri instead of rewritten one
        uri = ctx.var.uri
    else
        uri = ctx.var.upstream_uri

        -- the rewritten one may contain new args
        local index = core.string.find(uri, "?")
        if index then
            local raw_uri = uri
            uri = str_sub(raw_uri, 1, index - 1)
            args = str_sub(raw_uri, index + 1)
        end
    end
    local params = {
        path = uri,
        query = args or ctx.var.args,
        headers = include_req_headers(ctx),
        method = core.request.get_method(),
    }

    local body, err = core.request.get_body()
    if err then
        return nil, err
    end

    if body then
        params["body"] = body
    end

    local res, err = httpc:request(params)
    if not res then
        return nil, err
    end

    return res, err
end


function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.response(conf, ctx)
    local res, err = get_response(ctx)
    if not res or err then
        core.log.error("failed to request: ", err or "")
        return 502
    end
    ctx.runner_ext_response = res

    core.log.info("response info, status: ", res.status)

    -- Filter out exclude_resp_header headeres
    for k, v in pairs(res.headers) do
        if not exclude_resp_header[str_lower(k)] then
            core.response.set_header(k, v)
        end
    end

    local code, body = ext.communicate(conf, ctx, name, constants.RPC_HTTP_RESP_CALL)
    if code or body then
        -- TODO: chunk
        return code, body
    end
    core.log.info("ext-plugin will send response")
    -- send origin response

    ngx.status = res.status

    local reader = res.body_reader
    repeat
        local chunk, ok, read_err, print_err

        chunk, read_err = reader()
        if read_err then
            core.error.log("read response failed: ", read_err)
        end

        if chunk then
            ok, print_err = ngx_print(chunk)
            if not ok then
                core.error.log("output response failed: ", print_err)
            end
        end

        if read_err or print_err then
            return 502
        end
    until not chunk

    ngx_flush(true)
end


return _M
