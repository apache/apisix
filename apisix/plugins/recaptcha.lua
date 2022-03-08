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
local radix = require("resty.radixtree")
local core = require("apisix.core")
local http = require("resty.http")

local ipairs = ipairs
local table = table

local schema = {
    type = "object",
    properties = {
        recaptcha_secret_key = { type = "string" },
        apis = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    path = { type = "string" },
                    methods = { type = "array", items = { type = "string" }, minItems = 1 },
                    param_from = {
                        type = "string",
                        default = "header",
                        enum = { "header", "query" }
                    },
                    param_name = { type = "string", default = "captcha" },
                }
            },
            minItems = 1
        },
        response = {
            type = "object",
            properties = {
                content_type = { type = "string", default = "application/json; charset=utf-8" },
                status_code = { type = "number", default = 400 },
                body = { type = "string", default = '{"message": "invalid captcha"}' }
            }
        },

    },
    additionalProperties = false,
    required = { "recaptcha_secret_key" },
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

local function build_radixtree(apis)
    local items = {}
    for _, api in ipairs(apis) do
        local item = {
            paths = { api.path },
            methods = api.methods,
            metadata = api,
        }
        table.insert(items, item)
    end
    return radix.new(items)
end

local function find_api(request, apis)
    local rx = build_radixtree(apis)
    return rx:match(request.path, { method = request.method })
end

local function retrieve_captcha(ctx, api)
    local captcha
    if api.param_from == "header" then
        captcha = core.request.header(ctx, api.param_name)
    elseif api.param_from == "query" then
        local uri_args = core.request.get_uri_args(ctx) or {}
        captcha = uri_args[api.param_name]
    end
    return captcha
end

function _M.access(conf, ctx)
    local path = ctx.var.uri
    local method = core.request.get_method()

    core.log.debug("path: ", path, ", method: ", method, ", conf: ", core.json.encode(conf))

    local api = find_api({ path = path, method = method }, conf.apis)
    if not api then
        return
    end

    core.log.debug("api found: ", core.json.encode(api))

    local invalid_captcha = true
    local captcha = retrieve_captcha(ctx, api)
    if captcha ~= nil and captcha ~= "" then
        local httpc = http.new()
        local secret = conf.recaptcha_secret_key
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
