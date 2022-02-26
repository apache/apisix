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
local http = require("resty.http")
local session = require("resty.session")
local ngx = ngx

local plugin_name = "auth-casdoor"
local schema = {
    type = "object",
    properties = {
        --Note: endpoint_addr and callback_url should not end with '/'
        endpoint_addr = {type = "string", pattern = "^[^%?]+[^/]$"},
        client_id = {type = "string"},
        client_secret = {type = "string"},
        callback_url = {type = "string", pattern = "^[^%?]+[^/]$"},
    },
    required = {
        "callback_url", "endpoint_addr", "client_id", "client_secret"
    }
}

local _M = {
    version = 0.1,
    priority = 2559,
    name = plugin_name,
    schema = schema
}

local function fetch_access_token(ctx, conf)
    local args = core.request.get_uri_args(ctx)
    if not args or not args.code or not args.state then
        return nil, "failed when accessing token. Invalid code or state"
    end
    local client = http.new()
    local url = conf.endpoint_addr .. "/api/login/oauth/access_token"

    local res, err = client:request_uri(url, {
        method = "POST",
        query = {
            code = args.code,
            grant_type = "authorization_code",
            client_id = conf.client_id,
            client_secret = conf.client_secret
        }
    })
    if not res then return nil, err end
    local data, err = core.cjson.decode(res.body)

    if err or not data then
        err = "failed to parse casdoor response data: " .. err
        return nil, err
    end

    if not data.access_token then
        return nil, "failed when accessing token: no access_token contained"
    end

    return data.access_token, nil
end

function _M.check_schema(conf) return core.schema.check(schema, conf) end

function _M.access(conf, ctx)
    -- log.info("hit auth-casdoor access")
    local current_uri = ctx.var.uri
    local session_obj_read, session_present = session.open()

    -- step 1: check whether hits the callback
    local real_callback_url=ngx.re.match(conf.callback_url, ".-//[^/]+(/.*)")
    if current_uri == real_callback_url then
        local access_token, err = fetch_access_token(ctx, conf)
        if access_token then
            if not session_present then
                return 503, "no session found"
            end
            local original_url = session_obj_read.data.original_uri
            if not original_url then
                return 503, "no original_url found in session"
            end
            local session_obj_write = session.start()
            session_obj_write.data.access_token = access_token
            session_obj_write:save()
            core.response.set_header("Location", original_url)
            return 302
        else
            return 503, err
        end
    end

    -- step 2: check whether session exists
    if not (session_present and session_obj_read.data.access_token) then
        -- session not exists, redirect to login page
        local session_obj_write = session.start()
        session_obj_write.data.original_uri = current_uri
        session_obj_write:save()
        local redirect_url = conf.endpoint_addr ..
                                 "/login/oauth/authorize?response_type=code&scope=read" ..
                                 "&state=casdoor&client_id=" .. conf.client_id ..
                                 "&redirect_uri=" .. conf.callback_url
        core.response.set_header("Location", redirect_url)
        return 302
    end

end

return _M
