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

local base64_encode = ngx.encode_base64
local ngx_time = ngx.time
local type = type

local DEFAULT_TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v2/oauth/token"
local DEFAULT_USERINFO_URL = "https://open.feishu.cn/open-apis/authen/v1/user_info"

local schema = {
    type = "object",
    properties = {
        app_id = {type = "string", minLength = 1},
        app_secret = {type = "string", minLength = 1},
        code_header = {
            type = "string",
            description = "Header name to extract authorization code from.",
            default = "X-Feishu-Code"
        },
        code_query = {
            type = "string",
            description = "Query parameter name to extract authorization code from.",
            default = "code"
        },
        userinfo_url = {
            type = "string",
            default = DEFAULT_USERINFO_URL
        },
        access_token_url = {
            type = "string",
            default = DEFAULT_TOKEN_URL
        },
        set_userinfo_header = {
            type = "boolean",
            description = "Whether to set feishu user information in request headers",
            default = true
        },
        auth_redirect_uri = {
            type = "string",
            description = "Redirect URI for initiating Feishu OAuth flow",
        },
        redirect_uri = {type = "string"},
        timeout = {type = "integer", default = 6000},
        ssl_verify = {type = "boolean", default = true},
        secret = {
            type = "string",
            description = "Secret used for key derivation.",
            minLength = 8,
            maxLength = 32,
        },
        secret_fallbacks = {
            type = "array",
            items = {
                type = "string",
                minLength = 8,
                maxLength = 32,
            },
            description = "List of secrets for alternative secrets used when doing key rotation"
        },
        cookie_expires_in = {
            type = "integer",
            description = "Valid duration (in seconds) for the authorization cookie."
                        .. "This value defines how long the cookie remains valid after creation.",
            default = 86400,
        },

    },
    encrypt_fields = {"app_secret", "secret"},
    required = {"app_id", "app_secret", "secret", "auth_redirect_uri", "redirect_uri"},
}

local _M = {
    version = 0.1,
    priority = 2420,
    name = "feishu-auth",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function fetch_access_token(conf, code)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local body = {
        grant_type = "authorization_code",
        client_id = conf.app_id,
        client_secret = conf.app_secret,
        redirect_uri = conf.auth_redirect_uri,
        code = code,
    }

    local res, err = httpc:request_uri(conf.access_token_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = core.json.encode(body),
        ssl_verify = conf.ssl_verify
    })

    if not res then
        core.log.error("failed to get feishu token: ", err)
        return nil, nil, err
    end

    core.log.debug("request feishu access token response status: ",
                                    res.status)

    if res.status ~= 200 then
        core.log.warn("unexpected http response status from feishu: ",
                                        res.status, ", body: ", res.body)
        return nil, nil, "unexpected response status: " .. res.status
                                            .. ", body: " .. res.body
    end

    local data, err = core.json.decode(res.body)
    if not data then
        core.log.error("failed to decode feishu token response: ", err)
        return nil, nil, "failed to decode response: " .. (err or "nil")
    end

    if not data.access_token or type(data.expires_in) ~= "number" then
        core.log.error("feishu token response missing access_token or expires_in: ", res.body)
        return nil, nil, "missing access_token or expires_in in response"
    end

    return data.access_token, data.expires_in, nil
end


local function fetch_userinfo(conf, access_token)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(conf.userinfo_url, {
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. access_token,
        },
        ssl_verify = conf.ssl_verify
    })

    if not res then
        core.log.error("failed to verify feishu user: ", err)
        return nil, err
    end

    core.log.debug("request feishu userinfo response status: ", res.status, ", body: ", res.body)

    if res.status ~= 200 then
        core.log.error("unexpected http response status from feishu: ",
                            res.status, ", body: ", res.body)
        return nil, "unexpected http response status: " .. res.status
    end

    local data, err = core.json.decode(res.body)
    if not data then
        core.log.error("failed to decode feishu userinfo response: ", err, ", body: ", res.body)
        return nil, "failed to decode response: " .. err
    end

    if data.code ~= 0 then
        core.log.warn("failed to get feishu userinfo: ", res.body)
        return nil, "unexpected error code: " .. data.code
                            .. ", errmsg: " .. (data.msg or "nil")
    end

    return data.data, nil
end


local function get_code(conf, ctx)
    local code = core.request.header(ctx, conf.code_header)
    if not code then
        local uri_args = core.request.get_uri_args(ctx) or {}
        code = uri_args[conf.code_query]
    end

    return code
end


function _M.rewrite(conf, ctx)
    local userinfo, err

    local sess, sess_err = session.open(
        {
            secret = conf.secret,
            secret_fallbacks = conf.secret_fallbacks,
            cookie_name = "feishu_session",
            absolute_timeout = conf.cookie_expires_in,
        }
    )
    if not sess then
        core.log.error("failed to open session: ", sess_err)
        return 500, {message = "Failed to open session"}
    end

    local raw = sess:get("userinfo")
    if raw then
        userinfo, err = core.json.decode(raw)
        if not userinfo then
            sess:destroy()
            core.log.error("failed to decode userinfo in session: ", err)
            return 500, {message = "Invalid userinfo in session"}
        end
    else
        local code = get_code(conf, ctx)
        if not code then
            core.response.set_header("Location", conf.redirect_uri)
            return 302
        end

        local refreshed = true
        local access_token = sess:get("access_token")
        if access_token then
            local expires_at = sess:get("access_token_expires_at")
            if expires_at and ngx_time() < expires_at then
                refreshed = false
            else
                sess:delete("access_token")
                sess:delete("access_token_expires_at")
            end
        end

        if refreshed then
            local new_access_token, expires_in, err = fetch_access_token(conf, code)
            if not new_access_token then
                core.log.warn("failed to get feishu access token: ", err)
                return 401, {
                    message = "Invalid authorization code",
                }
            end
            access_token = new_access_token
            sess:set("access_token", access_token)
            sess:set("access_token_expires_at", ngx_time() + expires_in - 60)
        end

        local new_userinfo, err = fetch_userinfo(conf, access_token)
        if not new_userinfo then
            core.log.warn("failed to get feishu userinfo: ", err)
            sess:destroy()
            return 401, {
                message = "Invalid authorization code",
            }
        end
        userinfo = new_userinfo
        local raw, err = core.json.encode(userinfo)
        if not raw then
            core.log.error("failed to encode userinfo: ", err)
            return 500, {message = "Invalid userinfo"}
        end

        sess:set("userinfo", raw)
        sess:save()
        core.log.info("verified feishu user, code: ", code,
                        ", app_id: ", conf.app_id)
    end

    if userinfo and conf.set_userinfo_header ~= false then
        core.request.set_header(ctx, "X-Userinfo", base64_encode(core.json.encode(userinfo)))
    end
    ctx.external_user = userinfo
end


return _M
