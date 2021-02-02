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
local http = require("resty.http")
local ipairs = ipairs
local ngx = ngx
local tostring = tostring
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local string = string

local plugin_name = "auth-hook"

local lrucache = core.lrucache.new({
    type = "plugin"
})

local hook_lrucache = core.lrucache.new({
    ttl = 60, count = 1024
})

local schema = {
    type = "object",
    properties = {
        hook_uri = {type = "string", minLength = 1, maxLength = 4096},
        auth_id = {type = "string", minLength = 1, maxLength = 100},
        hook_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        hook_args = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        hook_res_to_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        hook_res_to_header_prefix = {type = "string", minLength = 1, maxLength = 100},
        hook_cache = {type = "boolean", default = false},
    },
    required = { "hook_uri","auth_id" },
}



local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    core.log.warn("input conf: ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end

-- 获取配置缓存
local create_consume_cache
do
    local consumer_names = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer_val in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer_val))
            consumer_names[consumer_val.auth_conf.auth_id] = consumer_val
        end
        return consumer_names
    end

end


local function get_auth_id(ctx)

    local auth_id = ctx.var.http_x_auth_id
    if auth_id then
        return auth_id
    end

    auth_id = ctx.var.arg_auth_id
    if auth_id then
        return auth_id
    end

    return nil;
end

local function get_auth_token(ctx)

    local token = ctx.var.http_x_auth_token
    if token then
        return token
    end

    token = ctx.var.http_authorization
    if token then
        return token
    end

    token = ctx.var.arg_auth_token
    if token then
        return token
    end

    local cookie, err = ck:new()
    if not cookie then
        return nil, err
    end

    local val, err = cookie:get("auth-token")
    return val, err
end

local function fail_response(message, init_values)
    local response = init_values or {}
    response.message = message
    return response
end

--初始化headers

local function new_table()
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

local function get_config(auth_id)
    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        core.response.exit(500)
    end
    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
            create_consume_cache, consumer_conf)
    local config = consumers[auth_id]
    if not config then
        core.log.info("request auth_id [", auth_id, "] not found")
        core.response.exit(400, fail_response("auth_id [" .. tostring(auth_id) .. "] not found", { status_code = 400 }))
    end
    return config.auth_conf
end


--获取需要传输的headers
local function request_headers(config, ctx)
    local req_headers = new_table();
    local headers = core.request.headers(ctx);
    local hook_headers = config.hook_headers
    if not hook_headers then
        return req_headers
    end
    for field in pairs(hook_headers) do
        local v = headers[field]
        if v then
            req_headers[field] = v
        end
    end
    return req_headers;
end

--获取需要传输的headers
local function res_to_headers(config, data)

    local prefix = config.hook_res_to_header_prefix or ''
    local hook_res_to_headers = config.hook_res_to_headers;
    if (not hook_res_to_headers) or (not data) then
        return
    end

    for field in pairs(hook_res_to_headers) do
        local v = data[field]
        if v then
            if type(v) == "table" then
                v = core.json.delay_encode(perm_item)
            end
            local f = string.gsub(field, '_', '-')
            core.response.set_header(prefix .. f, v)
            core.request.set_header(prefix .. f, v)
        end
    end
    return ;
end

--获取需要传输的args
local function request_args(hook_args)

    if not hook_args then
        return nil
    end

    local req_args = new_table();
    local args = ngx.req.get_uri_args()
    for field in pairs(hook_args) do
        local v = args[field]
        if v then
            req_args[field] = v
        end
    end
    return req_args;
end


-- timeout in ms
local function http_req(method, uri, body, myheaders, timeout)
    if myheaders == nil then
        myheaders = new_table()
    end

    local httpc = http.new()
    if timeout then
        httpc:set_timeout(timeout)
    end

    local params = { method = method, headers = myheaders, body = body, ssl_verify = false }
    local res, err = httpc:request_uri(uri, params)
    if err then
        core.log.error("FAIL REQUEST [ ", core.json.delay_encode({ method = method, uri = uri, body = body, headers = myheaders }), " ] failed! res is nil, err:", err)
        return nil, err
    end

    return res
end

local function http_get(uri, myheaders, timeout)
    return http_req("GET", uri, nil, myheaders, timeout)
end

local function get_auth_info(config, ctx, hook_url, action, path, client_ip, auth_token)
    local retry_max = 2
    local timeout = 1000 * 10
    local errmsg
    local res
    local err
    local headers = request_headers(config, ctx)
    headers["X-client-id"] = client_ip
    headers["Authorization"] = auth_token
    headers["Content-Type"] = "application/json; charset=utf-8"
    local args = request_args(config.hook_args)
    args['hook_path'] = path
    args['hook_action'] = action
    args['hook_client_ip'] = client_ip
    local url = hook_url .. "?" .. ngx.encode_args(args)
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
        errmsg = body.message
        return { status = res.status, err = errmsg, body = body }
    end
end

function _M.rewrite(conf, ctx)
    local url = ctx.var.uri
    local action = ctx.var.request_method
    local client_ip = ctx.var.http_x_real_ip or core.request.get_ip(ctx)
    --local auth_id = get_auth_id(ctx)
    --local config = get_config(auth_id)
    local config = conf
    local perm_item = {action = action, url = url, clientIP = client_ip }
    --core.log.error("hit web-auth rewrite")

    local auth_token, err = get_auth_token(ctx)
    if not auth_token then
        core.log.info("no permission to access ", core.json.delay_encode(perm_item), ", need login!")
        return 401, fail_response("Missing auth token in request", { status_code = 401 })
    end

    local hook_uri = config.hook_uri
    local res
    if config.hook_cache then
        res = hook_lrucache(plugin_name .. "#" .. auth_token, config.version, get_auth_info, config, ctx, hook_uri, action, url, client_ip, auth_token)
    else
        res = get_auth_info(config, ctx, hook_uri, action, url, client_ip, auth_token)
    end
    core.log.info(" get_auth_info(", core.json.delay_encode(perm_item), ") res: ", core.json.delay_encode(res))

    local data
    if res.body then
        data = res.body
        if data then
            ctx.auth_data = data
            res_to_headers(config, data)
        end
    end

    if res.status ~= 200 then
        -- no permission.
        core.log.error(" get_auth_info(", core.json.delay_encode(perm_item), ") failed, res: ", core.json.delay_encode(res))
        return 401, fail_response(res.err, { status_code = 401 })
    end
    core.log.info("web-auth check permission passed")
end

return _M
