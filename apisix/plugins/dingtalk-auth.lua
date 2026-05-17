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

-- the access token from dingtalk has a TTL of 7200 seconds,
-- we set the cache TTL to 7000 seconds to avoid edge cases of token expiration during use.
local access_token_cache = core.lrucache.new({
    ttl = 7000,
    invalid_stale = true,
})

local DEFAULT_USERINFO_URL = "https://oapi.dingtalk.com/topapi/v2/user/getuserinfo"
local DEFAULT_TOKEN_URL = "https://api.dingtalk.com/v1.0/oauth2/accessToken"

local schema = {
    type = "object",
    properties = {
        app_key = {type = "string", minLength = 1},
        app_secret = {type = "string", minLength = 1},
        code_header = {
            type = "string",
            description = "HTTP header name to extract dingtalk authorization code from.",
            default = "X-DingTalk-Code"
        },
        code_query = {
            type = "string",
            description = "Query parameter name to extract dingtalk authorization code from.",
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
            description = "Whether to set dingtalk user information in request headers",
            default = true
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
    required = {"app_key", "app_secret", "secret", "redirect_uri"},
}

local _M = {
    version = 0.1,
    priority = 2430,
    name = "dingtalk-auth",
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function fetch_access_token(conf)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local body = {
        appKey = conf.app_key,
        appSecret = conf.app_secret
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
        core.log.error("failed to get dingtalk token: ", err)
        return nil, err
    end

    core.log.debug("request dingtalk access token response status: ",
                                    res.status)

    if res.status ~= 200 then
        core.log.error("unexpected http response status from dingtalk: ",
                                        res.status, ", body: ", res.body)
        return nil, "unexpected response status: " .. res.status
    end

    local data, err = core.json.decode(res.body)
    if not data then
        core.log.error("failed to decode dingtalk token response: ", err)
        return nil, "failed to decode response: " .. (err or "nil")
    end

    local access_token = data.accessToken
    if not access_token then
        core.log.error("dingtalk token response missing accessToken: ", res.body)
        return nil, "dingtalk token response missing accessToken"
    end
    return access_token, nil
end


local function fetch_userinfo(conf, access_token, code)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local params = {
        access_token = access_token,
    }

    local body = {
        code = code
    }

    local res, err = httpc:request_uri(conf.userinfo_url, {
        method = "POST",
        query = params,
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = core.json.encode(body),
        ssl_verify = conf.ssl_verify
    })

    if not res then
        core.log.error("failed to verify dingtalk user: ", err)
        return nil, err
    end

    core.log.debug("request dingtalk userinfo response status: ", res.status, ", body: ", res.body)

    if res.status ~= 200 then
        core.log.error("unexpected http response status from dingtalk: ",
                            res.status, ", body: ", res.body)
        return nil, "unexpected http response status: " .. res.status
    end

    local data, err = core.json.decode(res.body)
    if not data then
        core.log.error("failed to decode dingtalk userinfo response: ", err)
        return nil, "failed to decode response: " .. err
    end

    if data.errcode ~= 0 then
        return nil, "unexpected error code: " .. data.errcode
                            .. ", errmsg: " .. (data.errmsg or "nil")
    end

    return data.result, nil
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
            cookie_name = "dingtalk_session",
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

        local key = core.table.concat({
            conf.access_token_url,
            conf.app_key,
            conf.app_secret,
        }, "#")
        local access_token, err = access_token_cache(key, nil,
                                        fetch_access_token, conf)
        if not access_token then
            core.log.error("failed to get dingtalk access token: ", err)
            return 500, {
                message = "Invalid configuration",
            }
        end

        local new_userinfo, err = fetch_userinfo(conf, access_token, code)
        if not new_userinfo then
            core.log.warn("failed to get dingtalk userinfo: ", err)
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
        local ok, save_err = sess:save()
        if not ok then
            core.log.error("failed to save session: ", save_err)
            return 500, {message = "Failed to save session"}
        end
        core.log.info("verified dingtalk user, code: ", code,
                        ", app_key: ", conf.app_key)
    end

    if userinfo and conf.set_userinfo_header ~= false then
        local raw_for_header, encode_err = core.json.encode(userinfo)
        if raw_for_header then
            core.request.set_header(ctx, "X-Userinfo", base64_encode(raw_for_header))
        else
            core.log.warn("failed to encode userinfo for X-Userinfo header: ", encode_err)
        end
    end
    ctx.external_user = userinfo
end


return _M
