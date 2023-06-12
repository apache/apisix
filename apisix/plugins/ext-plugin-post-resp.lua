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
local helper = require("apisix.plugins.ext-plugin.helper")
local constants = require("apisix.constants")
local http = require("resty.http")

local ngx       = ngx
local ngx_print = ngx.print
local ngx_flush = ngx.flush
local string    = string
local str_sub   = string.sub


local name = "ext-plugin-post-resp"
local _M = {
    version = 0.1,
    priority = -4000,
    name = name,
    schema = ext.schema,
}


local function include_req_headers(ctx)
    -- TODO: handle proxy_set_header
    return core.request.headers(ctx)
end


local function close(http_obj)
    -- TODO: keepalive
    local ok, err = http_obj:close()
    if not ok then
        core.log.error("close http object failed: ", err)
    end
end


local function get_response(ctx, http_obj)
    local ok, err = http_obj:connect({
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

    local res, err = http_obj:request(params)
    if not res then
        return nil, err
    end

    return res, err
end

local function send_chunk(chunk)
    if not chunk then
        return nil
    end

    local ok, print_err = ngx_print(chunk)
    if not ok then
        return "output response failed: ".. (print_err or "")
    end
    local ok, flush_err = ngx_flush(true)
    if not ok then
        core.log.warn("flush response failed: ", flush_err)
    end

    return nil
end

-- TODO: response body is empty (304 or HEAD)
-- If the upstream returns 304 or the request method is HEAD,
-- there is no response body. In this case,
-- we need to send a response to the client in the plugin,
-- instead of continuing to execute the subsequent plugin.
local function send_response(ctx, res, code)
    ngx.status = code or res.status

    local chunks = ctx.runner_ext_response_body
    if chunks then
        for i=1, #chunks do
            local err = send_chunk(chunks[i])
            if err then
                return err
            end
        end
        return
    end

    return helper.response_reader(res.body_reader, send_chunk)
end


function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.before_proxy(conf, ctx)
    local http_obj = http.new()
    local res, err = get_response(ctx, http_obj)
    if not res or err then
        core.log.error("failed to request: ", err or "")
        close(http_obj)
        return 502
    end
    ctx.runner_ext_response = res

    core.log.info("response info, status: ", res.status)
    core.log.info("response info, headers: ", core.json.delay_encode(res.headers))

    local code, body = ext.communicate(conf, ctx, name, constants.RPC_HTTP_RESP_CALL)
    if body then
        close(http_obj)
        -- if the body is changed, the code will be set.
        return code, body
    end
    core.log.info("ext-plugin will send response")

    -- send origin response, status maybe changed.
    err = send_response(ctx, res, code)
    close(http_obj)

    if err then
        core.log.error(err)
        return not ngx.headers_sent and 502 or nil
    end

    core.log.info("ext-plugin send response succefully")
end


return _M
