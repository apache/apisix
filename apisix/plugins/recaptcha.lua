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

local schema = {
    type = "object",
    properties = {
        secret_key = { type = "string" },
        parameter_source = { type = "string", default = "header", enum = { "header", "query" } },
        parameter_name = { type = "string", default = "captcha" },
        response = {
            type = "object",
            properties = {
                content_type = { type = "string", default = "application/json; charset=utf-8" },
                status_code = { type = "number", default = 400 },
                body = { type = "string", default = '{"message": "invalid captcha"}' }
            }
        },
    },
    required = { "secret_key" },
}

local recaptcha_url = "https://www.recaptcha.net"

local _M = {
    version = 0.1,
    priority = 700,
    name = "recaptcha",
    schema = schema,
}

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

local function retrieve_captcha(ctx, conf)
    local captcha
    if conf.parameter_source == "header" then
        captcha = core.request.header(ctx, conf.parameter_name)
    elseif conf.parameter_source == "query" then
        local uri_args = core.request.get_uri_args(ctx) or {}
        captcha = uri_args[conf.parameter_name]
    end
    return captcha
end

function _M.access(conf, ctx)
    local path = ctx.var.uri
    local method = core.request.get_method()

    core.log.debug("path: ", path, ", method: ", method, ", conf: ", core.json.encode(conf))

    local invalid_captcha = true
    local captcha = retrieve_captcha(ctx, conf)
    if captcha ~= nil and captcha ~= "" then
        local httpc = http.new()
        local secret = conf.secret_key
        local remote_ip = core.request.get_remote_client_ip(ctx)
        local res, err = httpc:request_uri(recaptcha_url .. "/recaptcha/api/siteverify", {
            method = "POST",
            body = "secret=" .. secret .. "&response=" .. captcha .. "&remoteip=" .. remote_ip,
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded",
            },
            ssl_verify = false
        })
        if err then
            core.log.error("request failed: ", err)
            return 500
        end
        core.log.debug("recaptcha veirfy result: ", res.body)
        local recaptcha_result = core.json.decode(res.body)
        if recaptcha_result.success == true then
            invalid_captcha = false
        end
    end

    if invalid_captcha then
        core.response.set_header("Content-Type", conf.response.content_type)
        return conf.response.status_code, core.utils.resolve_var(conf.response.body, ctx.var)
    end

    return
end

return _M
