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
local consumer = require("apisix.consumer")
local json = require("apisix.core.json")
local sleep = core.sleep
local ngx_re = require("ngx.re")
local http = require("resty.http")
local ipairs = ipairs
local ngx = ngx
local tostring = tostring
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local type = type
local string = string

local plugin_name = "auth-hook"

local lrucache = core.lrucache.new({
    type = "plugin"
})
local req_lrucache = core.lrucache.new({
    ttl = 60, count = 1024
})

local schema = {
    type = "object",
    properties = {
        auth_id = {
            type = "string",
            default = "unset"
        },
        hook_uri = {
            type = "string"
        },
        hook_headers = {
            description = "需要代理请求服务hook的header列表",
            type = "array",
            items = {
                description = "header name",
                type = "string"
            }
        },
        hook_args= {
            description = "需要根据请求携带到hook参数中的字段",
            type = "array",
            items = {
                description = "arg name",
                type = "string",
            }
        },
        hook_cache = {
            type = "boolean",
            default = true
        },
        hook_cache_timeout = {
            description = "hook 超时时间",
            type = "integer",
            minimum = 1000,
            default = 2000
        },
    },
    required = { "hook_uri" }

}

local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}

-- 获取配置缓存
local create_consume_cache
do
    local consumer_names = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_names[consumer.auth_conf.auth_id] = consumer
        end

        return consumer_names
    end

end -- do

--获取请求缓存
local token_auth_cache
do
    local token_anth = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_names[consumer.auth_conf.auth_id] = consumer
        end

        return consumer_names
    end

end -- do


local function fail_response(message, init_values)
    local response = init_values or {}
    response.message = message
    return response
end

local function success_response(message, init_values)
    local response = init_values or {}
    response.message = message
    return response
end


--获取需要传输的headers
local function request_headers()

    local req_headers = new_headers();
    for field in pairs(conf.headers) do
        local v = core.request.header(ctx,field)
        if  v then
            req_headers[field] = v
        end
    end
    return req_headers;
end

--初始化headers

local function new_headers()
    local t = {}
    local lt = {}
    local _mt = {
        __index = function(t, k)
            return rawget(lt, string.lower(k))
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(lt, string.lower(k), v)
        end,
    }
    return setmetatable(t, _mt)
end


-- timeout in ms
local function http_req(method, uri, body, myheaders, timeout)
    if myheaders == nil then
        myheaders = new_headers()
    end

    local httpc = http.new()
    if timeout then
        httpc:set_timeout(timeout)
    end

    local params = { method = method, headers = myheaders, body = body,
                     ssl_verify = false }
    local res, err = httpc:request_uri(uri, params)
    if err then
        core.log.error("FAIL REQUEST [ ", core.json.delay_encode(
                { method = method, uri = uri, body = body, headers = myheaders }),
                " ] failed! res is nil, err:", err)
        return nil, err
    end

    return res
end



local function http_get(uri, myheaders, timeout)
    return http_req("GET", uri, nil, myheaders, timeout)
end


function _M.check_schema(conf)
    core.log.info("input conf: ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function get_auth_token(ctx)
    if ctx.var.arg_auth_token then
        return ngx.unescape_uri(ctx.var.arg_auth_token)
    end

    if ctx.var.http_authorization then
        return ctx.var.http_authorization
    end

    if ctx.var.http_x_auth_token then
        return ctx.var.http_x_auth_token
    end

    return ctx.var['cookie_x-auth-token']
end

local function get_auth_info(hook_url, auth_id, action, path, client_ip, auth_token)
    local retry_max = 2
    local errmsg
    local userInfo
    local res
    local err
    local headers = request_headers()
    headers["X-client-id"] = client_ip
    headers["Authorization"] = auth_token
    headers["Content-Type"] = "application/json; charset=utf-8"
    local args = { auth_id = auth_id, path = path, action = action, clientIP = client_ip }
    local url = hook_url .. "?" .. ngx.encode_args(args)
    local timeout = 1000 * 10

    for i = 1, retry_max do
        -- TODO: read apisix info.
        res, err = http_get(url, headers, timeout)
        if err then
            break
        else
            core.log.info("check permission request:", url, ", status:", res.status,
                    ",body:", core.json.delay_encode(res.body))
            if res.status < 500 then
                break
            else
                core.log.info("request [curl -v ", url, "] failed! status:", res.status)
                if i < retry_max then
                    sleep(0.1)
                end
            end
        end
    end

    if err then
        core.log.error("fail request: ", url, ", err:", err)
        return {
            status = 500,
            err = "request to web-server failed, err:" .. err
        }
    end

    if res.status ~= 200 and res.status ~= 401 then
        return {
            status = 500,
            err = 'request to web-server failed, status:' .. res.status
        }
    end

    local body, err = json.decode(res.body)
    if err then
        errmsg = 'check permission failed! parse response json failed!'
        core.log.error("json.decode(", res.body, ") failed! err:", err)
        return { status = res.status, err = errmsg }
    else
        if body.data then
            userInfo = body.data.userInfo
        end
        errmsg = body.message
        return { status = res.status, err = errmsg, body = body }
    end
end



local function get_args()
    local ctx = ngx.ctx.api_ctx
    local args, err
    ngx.req.read_body()
    if string.find(ctx.var.http_content_type or "", "application/json",
            1, true) then
        args, err = json.decode(ngx.req.get_body_data())
        if err then
            core.log.error("json.decode(", ngx.req.get_body_data(), ") failed! ", err)
        end
    else
        args = ngx.req.get_post_args()
    end

    return args
end


local function get_config(auth_id)
    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        core.response.exit(500)
    end

    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    core.log.info("------ consumers: ", core.json.delay_encode(consumers))
    local config = consumers[auth_id]
    if not config then
        core.log.info("request auth_id [", auth_id, "] not found")
        core.response.exit(400,
                fail_response("auth_id [" .. tostring(auth_id) .. "] not found")
        )
    end
    return config.auth_conf
end




function _M.rewrite(conf, ctx)
    local url = ctx.var.uri
    local action = ctx.var.request_method
    local client_ip = ctx.var.http_x_real_ip or core.request.get_ip(ctx)
    local auth_id = ctx.var.http_x_auth_id
    local perm_item = { auth_id = auth_id, action = action, url = url, clientIP = client_ip }
    core.log.info("hit web-auth rewrite")

    local auth_token = get_auth_token(ctx)
    if auth_token == nil then
        core.log.info("no permission to access ",
                core.json.delay_encode(perm_item), ", need login!")
        return 401, fail_response("Missing auth token in request",{status_code=401})
    end

    local config = get_config(auth_id)

    local hook_uri = config.hook_uri

    local res = get_auth_info(hook_uri, auth_id, action, url,
            client_ip, auth_token)
    core.log.info(" check_url_permission(", core.json.delay_encode(perm_item),
            ") res: ", core.json.delay_encode(res))

    local username = nil
    local useraid = nil
    local nickname = nil
    if type(res.userInfo) == 'table' then
        local userInfo = res.userInfo
        ctx.userInfo = userInfo
        local userId = userInfo.id
        username = userInfo.username
        nickname = userInfo.nickname or userInfo.username
        local prefix = consumer.auth_conf.header_prefix or ''
        core.response.set_header(prefix .. "UserId", userId)
        core.response.set_header(prefix .. "Username", username)
        core.response.set_header(prefix .. "Nickname", ngx.escape_uri(nickname))
        core.request.set_header(prefix .. "UserId", userId)
        core.request.set_header(prefix .. "Username", username)
        core.request.set_header(prefix .. "Nickname", ngx.escape_uri(nickname))
    end

    if res.status ~= 200 then
        -- no permission.
        core.log.error(" check_url_permission(",
                core.json.delay_encode(perm_item),
                ") failed, res: ", core.json.delay_encode(res))
        return 401, fail_response(res.err,
                { username = username, nickname = nickname }
        )
    end
    core.log.info("web-auth check permission passed")
end



return _M
