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
local json_decode = require("toolkit.json").decode
local json_encode = require("toolkit.json").encode

local rsa_public_key = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw86xcJwNxL2MkWnjIGiw
94QY78Sq89dLqMdV/Ku2GIX9lYkbS0VDGtmxDGJLBOYW4cKTX+pigJyzglLgE+nD
z3VJf2oCqSV74gTyEdi7sw9e1rCyR6dR8VA7LEpIHwmhnDhhjXy1IYSKRdiVHLS5
sYmaAGckpUo3MLqUrgydGj5tFzvK/R/ELuZBdlZM+XuWxYry05r860E3uL+VdVCO
oU4RJQknlJnTRd7ht8KKcZb6uM14C057i26zX/xnOJpaVflA4EyEo99hKQAdr8Sh
G70MOLYvGCZxl1o8S3q4X67MxcPlfJaXnbog2AOOGRaFar88XiLFWTbXMCLuz7xD
zQIDAQAB
-----END PUBLIC KEY-----]]

local rsa_private_key = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDDzrFwnA3EvYyR
aeMgaLD3hBjvxKrz10uox1X8q7YYhf2ViRtLRUMa2bEMYksE5hbhwpNf6mKAnLOC
UuAT6cPPdUl/agKpJXviBPIR2LuzD17WsLJHp1HxUDssSkgfCaGcOGGNfLUhhIpF
2JUctLmxiZoAZySlSjcwupSuDJ0aPm0XO8r9H8Qu5kF2Vkz5e5bFivLTmvzrQTe4
v5V1UI6hThElCSeUmdNF3uG3wopxlvq4zXgLTnuLbrNf/Gc4mlpV+UDgTISj32Ep
AB2vxKEbvQw4ti8YJnGXWjxLerhfrszFw+V8lpeduiDYA44ZFoVqvzxeIsVZNtcw
Iu7PvEPNAgMBAAECggEAVpyN9m7A1F631/aLheFpLgMbeKt4puV7zQtnaJ2XrZ9P
PR7pmNDpTu4uF3k/D8qrIm+L+uhVa+hkquf3wDct6w1JVnfQ93riImbnoKdK13ic
DcEZCwLjByfjFMNCxZ/gAZca55fbExlqhFy6EHmMjhB8s2LsXcTHRuGxNI/Vyi49
sxECibe0U53aqdJbVWrphIS67cpwl4TUkN6mrHsNuDYNJ9dgkpapoqp4FTFQsBqC
afOK5qgJ68dWZ47FBUng+AZjdCncqAIuJxxItGVQP6YPsFs+OXcivIVHJr363TpC
l85FfdvqWV5OGBbwSKhNwiTNUVvfSQVmtURGWG/HbQKBgQD4gZ1z9+Lx19kT9WTz
lw93lxso++uhAPDTKviyWSRoEe5aN3LCd4My+/Aj+sk4ON/s2BV3ska5Im93j+vC
rCv3uPn1n2jUhWuJ3bDqipeTW4n/CQA2m/8vd26TMk22yOkkqw2MIA8sjJ//SD7g
tdG7up6DgGMP4hgbO89uGU7DAwKBgQDJtkKd0grh3u52Foeh9YaiAgYRwc65IE16
UyD1OJxIuX/dYQDLlo5KyyngFa1ZhWIs7qC7r3xXH+10kfJY+Q+5YMjmZjlL8SR1
Ujqd02R9F2//6OeswyReachJZbZdtiEw3lPa4jVFYfhSe0M2ZPxMwvoXb25eyCNI
1lYjSKq87wKBgHnLTNghjeDp4UKe6rNYPgRm0rDrhziJtX5JeUov1mALKb6dnmkh
GfRK9g8sQqKDfXwfC6Z2gaMK9YaryujGaWYoCpoPXtmJ6oLPXH4XHuLh4mhUiP46
xn8FEfSimuQS4/FMxH8A128GHQSI7AhGFFzlwfrBWcvXC+mNDsTvMmLxAoGARc+4
upppfccETQZ7JsitMgD1TMwA2f2eEwoWTAitvlXFNT9PYSbYVHaAJbga6PLLCbYF
FzAjHpxEOKYSdEyu7n/ayDL0/Z2V+qzc8KarDsg/0RgwppBbU/nUgeKb/U79qcYo
y4ai3UKNCS70Ei1dTMvmdpnwXwlxfNIBufB6dy0CgYBMYq9Lc31GkC6PcGEEbx6W
vjImOadWZbuOVnvEQjb5XCdcOsWsMcg96PtoeuyyHmhnEF1GsMzcIdQv/PHrvYpK
Yp8D0aqsLEgwGrJQER26FPpKmyIwvcL+nm6q5W31PnU9AOC/WEkB6Zs58hsMzD2S
kEJQcmfVew5mFXyxuEn3zA==
-----END PRIVATE KEY-----]]

local _M = {}


local function inject_headers()
    local hdrs = ngx.req.get_headers()
    for k, v in pairs(hdrs) do
        if k:sub(1, 5) == "resp-" then
            ngx.header[k:sub(6)] = v
        end
    end
end


function _M.hello()
    ngx.req.read_body()
    local s = "hello world"
    ngx.header['Content-Length'] = #s + 1
    ngx.say(s)
end


function _M.hello_chunked()
    ngx.print("hell")
    ngx.flush(true)
    ngx.print("o w")
    ngx.flush(true)
    ngx.say("orld")
end


function _M.hello1()
    ngx.say("hello1 world")
end


-- Fake endpoint, needed for testing authz-keycloak plugin.
function _M.course_foo()
    ngx.say("course foo")
end


function _M.server_port()
    ngx.print(ngx.var.server_port)
end
_M.server_port_route2 = _M.server_port
_M.server_port_hello = _M.server_port
_M.server_port_aa = _M.server_port


function _M.limit_conn()
    ngx.sleep(0.3)
    ngx.say("hello world")
end


function _M.plugin_proxy_rewrite()
    ngx.say("uri: ", ngx.var.uri)
    ngx.say("host: ", ngx.var.host)
    ngx.say("scheme: ", ngx.var.scheme)
    ngx.log(ngx.WARN, "plugin_proxy_rewrite get method: ", ngx.req.get_method())
end


function _M.plugin_proxy_rewrite_args()
    ngx.say("uri: ", ngx.var.uri)
    local args = ngx.req.get_uri_args()

    local keys = {}
    for k, _ in pairs(args) do
        table.insert(keys, k)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        if type(args[key]) == "table" then
            ngx.say(key, ": ", table.concat(args[key], ','))
        else
            ngx.say(key, ": ", args[key])
        end
    end
end


function _M.specific_status()
    local status = ngx.var.http_x_test_upstream_status
    if status ~= nil then
        ngx.status = status
        ngx.say("upstream status: ", status)
    end
end


function _M.status()
    ngx.log(ngx.WARN, "client request host: ", ngx.var.http_host)
    ngx.say("ok")
end


function _M.ewma()
    if ngx.var.server_port == "1981"
       or ngx.var.server_port == "1982" then
        ngx.sleep(0.2)
    else
        ngx.sleep(0.1)
    end
    ngx.print(ngx.var.server_port)
end


local builtin_hdr_ignore_list = {
    ["x-forwarded-for"] = true,
    ["x-forwarded-proto"] = true,
    ["x-forwarded-host"] = true,
    ["x-forwarded-port"] = true,
}

function _M.uri()
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()

    local keys = {}
    for k in pairs(headers) do
        if not builtin_hdr_ignore_list[k] then
            table.insert(keys, k)
        end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        ngx.say(key, ": ", headers[key])
    end
end
_M.uri_plugin_proxy_rewrite = _M.uri
_M.uri_plugin_proxy_rewrite_args = _M.uri


function _M.old_uri()
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()

    local keys = {}
    for k in pairs(headers) do
        table.insert(keys, k)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        ngx.say(key, ": ", headers[key])
    end
end


function _M.opentracing()
    ngx.say("opentracing")
end


function _M.with_header()
    --split into multiple chunk
    ngx.say("hello")
    ngx.say("world")
    ngx.say("!")
end


function _M.mock_zipkin()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    ngx.log(ngx.NOTICE, data)

    local spans = json_decode(data)
    local ver = ngx.req.get_uri_args()['span_version']
    if ver == "1" then
        if #spans ~= 5 then
            ngx.log(ngx.ERR, "wrong number of spans: ", #spans)
            ngx.exit(400)
        end
    else
        if #spans ~= 3 then
            -- request/proxy/response
            ngx.log(ngx.ERR, "wrong number of spans: ", #spans)
            ngx.exit(400)
        end
    end

    for _, span in pairs(spans) do
        local prefix = string.sub(span.name, 1, 6)
        if prefix ~= 'apisix' then
            ngx.log(ngx.ERR, "wrong prefix of name", prefix)
            ngx.exit(400)
        end
        if not span.traceId then
            ngx.log(ngx.ERR, "missing trace id")
            ngx.exit(400)
        end

        if not span.localEndpoint then
            ngx.log(ngx.ERR, "missing local endpoint")
            ngx.exit(400)
        end

        if span.localEndpoint.serviceName ~= 'APISIX'
          and span.localEndpoint.serviceName ~= 'apisix' then
            ngx.log(ngx.ERR, "wrong serviceName: ", span.localEndpoint.serviceName)
            ngx.exit(400)
        end

        if span.localEndpoint.port ~= 1984 then
            ngx.log(ngx.ERR, "wrong port: ", span.localEndpoint.port)
            ngx.exit(400)
        end

        local server_addr = ngx.req.get_uri_args()['server_addr']
        if server_addr then
            if span.localEndpoint.ipv4 ~= server_addr then
                ngx.log(ngx.ERR, "server_addr mismatched")
                ngx.exit(400)
            end
        end

    end
end


function _M.wolf_rbac_login_rest()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local args = json_decode(data)
    if not args.username then
        ngx.say(json_encode({ok=false, reason="ERR_USERNAME_MISSING"}))
        ngx.exit(0)
    end
    if not args.password then
        ngx.say(json_encode({ok=false, reason="ERR_PASSWORD_MISSING"}))
        ngx.exit(0)
    end
    if args.username ~= "admin" then
        ngx.say(json_encode({ok=false, reason="ERR_USER_NOT_FOUND"}))
        ngx.exit(0)
    end
    if args.password ~= "123456" then
        ngx.say(json_encode({ok=false, reason="ERR_PASSWORD_ERROR"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true, data={token="wolf-rbac-token",
        userInfo={nickname="administrator",username="admin", id="100"}}}))
end


function _M.wolf_rbac_access_check()
    local headers = ngx.req.get_headers()
    local token = headers['x-rbac-token']
    if token ~= 'wolf-rbac-token' then
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
        ngx.exit(0)
    end

    local args = ngx.req.get_uri_args()
    local resName = args.resName
    if resName == '/hello' or resName == '/wolf/rbac/custom/headers' then
        ngx.say(json_encode({ok=true,
                            data={ userInfo={nickname="administrator",
                                username="admin", id="100"} }}))
    elseif resName == '/hello/500' then
        ngx.status = 500
        ngx.say(json_encode({ok=false, reason="ERR_SERVER_ERROR"}))
    elseif resName == '/hello/401' then
        ngx.status = 401
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
    else
        ngx.status = 403
        ngx.say(json_encode({ok=false, reason="ERR_ACCESS_DENIED"}))
    end
end


function _M.wolf_rbac_user_info()
    local headers = ngx.req.get_headers()
    local token = headers['x-rbac-token']
    if token ~= 'wolf-rbac-token' then
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true,
                        data={ userInfo={nickname="administrator", username="admin", id="100"} }}))
end


function _M.wolf_rbac_change_pwd()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local args = json_decode(data)
    if args.oldPassword ~= "123456" then
        ngx.say(json_encode({ok=false, reason="ERR_OLD_PASSWORD_INCORRECT"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true, data={ }}))
end


function _M.wolf_rbac_custom_headers()
    local headers = ngx.req.get_headers()
    ngx.say('id:' .. headers['X-UserId'] .. ',username:' .. headers['X-Username']
            .. ',nickname:' .. headers['X-Nickname'])
end


function _M.websocket_handshake()
    local websocket = require "resty.websocket.server"
    local wb, err = websocket:new()
    if not wb then
        ngx.log(ngx.ERR, "failed to new websocket: ", err)
        return ngx.exit(400)
    end

    local bytes, err = wb:send_text("hello")
    if not bytes then
        ngx.log(ngx.ERR, "failed to send text: ", err)
        return ngx.exit(444)
    end
end
_M.websocket_handshake_route = _M.websocket_handshake


function _M.api_breaker()
    ngx.exit(tonumber(ngx.var.arg_code))
end


function _M.mysleep()
    ngx.sleep(tonumber(ngx.var.arg_seconds))
    if ngx.var.arg_abort then
        ngx.exit(ngx.ERROR)
    else
        ngx.say(ngx.var.arg_seconds)
    end
end


local function print_uri()
    ngx.say(ngx.var.uri)
end
for i = 1, 100 do
    _M["print_uri_" .. i] = print_uri
end

function _M.print_uri_detailed()
    ngx.say("ngx.var.uri: ", ngx.var.uri)
    ngx.say("ngx.var.request_uri: ", ngx.var.request_uri)
end

function _M.headers()
    local args = ngx.req.get_uri_args()
    for name, val in pairs(args) do
        ngx.header[name] = nil
        ngx.header[name] = val
    end

    ngx.say("/headers")
end


function _M.echo()
    ngx.req.read_body()
    local hdrs = ngx.req.get_headers()
    for k, v in pairs(hdrs) do
        ngx.header[k] = v
    end
    ngx.print(ngx.req.get_body_data() or "")
end


function _M.log()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local ct = ngx.var.content_type
    if ct ~= "text/plain" then
        body = json_decode(body)
        body = json_encode(body)
    end
    ngx.log(ngx.WARN, "request log: ", body or "nil")
end


function _M.server_error()
    error("500 Internal Server Error")
end


function _M.log_request()
    ngx.log(ngx.WARN, "uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()

    local keys = {}
    for k in pairs(headers) do
        table.insert(keys, k)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        ngx.log(ngx.WARN, key, ": ", headers[key])
    end
end


function _M.v3_auth_authenticate()
    ngx.log(ngx.WARN, "etcd auth failed!")
end


function _M._well_known_openid_configuration()
    local t = require("lib.test_admin")
    local openid_data = t.read_file("t/plugin/openid-connect/configuration.json")
    ngx.say(openid_data)
end

function _M.google_logging_token()
    local args = ngx.req.get_uri_args()
    local args_token_type = args.token_type or "Bearer"
    ngx.req.read_body()
    local data = ngx.decode_args(ngx.req.get_body_data())
    local jwt = require("resty.jwt")
    local access_scopes = "https://apisix.apache.org/logs:admin"
    local verify = jwt:verify(rsa_public_key, data["assertion"])
    if not verify.verified then
        ngx.status = 401
        ngx.say(json_encode({ error = "identity authentication failed" }))
        return
    end

    local scopes_valid = type(verify.payload.scope) == "string" and
            verify.payload.scope:find(access_scopes)
    if not scopes_valid then
        ngx.status = 403
        ngx.say(json_encode({ error = "no access to this scopes" }))
        return
    end

    local expire_time = (verify.payload.exp or ngx.time()) - ngx.time()
    if expire_time <= 0 then
        expire_time = 0
    end

    local jwt_token = jwt:sign(rsa_private_key, {
        header = { typ = "JWT", alg = "RS256" },
        payload = { exp = verify.payload.exp, scope = access_scopes }
    })

    ngx.say(json_encode({
        access_token = jwt_token,
        expires_in = expire_time,
        token_type = args_token_type
    }))
end

function _M.google_logging_entries()
    local args = ngx.req.get_uri_args()
    local args_token_type = args.token_type or "Bearer"
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local jwt = require("resty.jwt")
    local access_scopes = "https://apisix.apache.org/logs:admin"

    local headers = ngx.req.get_headers()
    local token = headers["Authorization"]
    if not token then
        ngx.status = 401
        ngx.say(json_encode({ error = "authentication header not exists" }))
        return
    end

    token = string.sub(token, #args_token_type + 2)
    local verify = jwt:verify(rsa_public_key, token)
    if not verify.verified then
        ngx.status = 401
        ngx.say(json_encode({ error = "identity authentication failed" }))
        return
    end

    local scopes_valid = type(verify.payload.scope) == "string" and
            verify.payload.scope:find(access_scopes)
    if not scopes_valid then
        ngx.status = 403
        ngx.say(json_encode({ error = "no access to this scopes" }))
        return
    end

    local expire_time = (verify.payload.exp or ngx.time()) - ngx.time()
    if expire_time <= 0 then
        ngx.status = 403
        ngx.say(json_encode({ error = "token has expired" }))
        return
    end

    ngx.say(data)
end

function _M.google_secret_token()
    local args = ngx.req.get_uri_args()
    local args_token_type = args.token_type or "Bearer"
    ngx.req.read_body()
    local data = ngx.decode_args(ngx.req.get_body_data())
    local jwt = require("resty.jwt")
    local access_scopes = "https://www.googleapis.com/auth/cloud"
    local verify = jwt:verify(rsa_public_key, data["assertion"])
    if not verify.verified then
        ngx.status = 401
        ngx.say(json_encode({ error = "identity authentication failed" }))
        return
    end

    local scopes_valid = type(verify.payload.scope) == "string" and
            verify.payload.scope:find(access_scopes)
    if not scopes_valid then
        ngx.status = 403
        ngx.say(json_encode({ error = "no access to this scopes" }))
        return
    end

    local expire_time = (verify.payload.exp or ngx.time()) - ngx.time()
    if expire_time <= 0 then
        expire_time = 0
    end

    local jwt_token = jwt:sign(rsa_private_key, {
        header = { typ = "JWT", alg = "RS256" },
        payload = { exp = verify.payload.exp, scope = access_scopes }
    })

    ngx.say(json_encode({
        access_token = jwt_token,
        expires_in = expire_time,
        token_type = args_token_type
    }))
end

function _M.google_secret_apisix_jack()
    local args = ngx.req.get_uri_args()
    local args_token_type = args.token_type or "Bearer"
    local jwt = require("resty.jwt")
    local access_scopes = "https://www.googleapis.com/auth/cloud"

    local headers = ngx.req.get_headers()
    local token = headers["Authorization"]
    if not token then
        ngx.status = 401
        ngx.say(json_encode({ error = "authentication header not exists" }))
        return
    end

    token = string.sub(token, #args_token_type + 2)
    local verify = jwt:verify(rsa_public_key, token)
    if not verify.verified then
        ngx.status = 401
        ngx.say(json_encode({ error = "identity authentication failed" }))
        return
    end

    local scopes_valid = type(verify.payload.scope) == "string" and
            verify.payload.scope:find(access_scopes)
    if not scopes_valid then
        ngx.status = 403
        ngx.say(json_encode({ error = "no access to this scopes" }))
        return
    end

    local expire_time = (verify.payload.exp or ngx.time()) - ngx.time()
    if expire_time <= 0 then
        ngx.status = 403
        ngx.say(json_encode({ error = "token has expired" }))
        return
    end

    local response = {
        name = "projects/647037004838/secrets/apisix/versions/1",
        payload = {
          data = "eyJrZXkiOiJ2YWx1ZSJ9",
          dataCrc32c = "2296192492"
        }
      }

    ngx.status = 200
    ngx.say(json_encode(response))
end

function _M.google_secret_fail_apisix_jack()
    local args = ngx.req.get_uri_args()
    local args_token_type = args.token_type or "Bearer"
    local jwt = require("resty.jwt")
    local access_scopes = "https://www.googleapis.com/auth/root/cloud"

    local headers = ngx.req.get_headers()
    local token = headers["Authorization"]
    if not token then
        ngx.status = 401
        ngx.say(json_encode({ error = "authentication header not exists" }))
        return
    end

    token = string.sub(token, #args_token_type + 2)
    local verify = jwt:verify(rsa_public_key, token)
    if not verify.verified then
        ngx.status = 401
        ngx.say(json_encode({ error = "identity authentication failed" }))
        return
    end

    local scopes_valid = type(verify.payload.scope) == "string" and
            verify.payload.scope:find(access_scopes)
    if not scopes_valid then
        ngx.status = 403
        ngx.say(json_encode({ error = "no access to this scopes" }))
        return
    end

    local expire_time = (verify.payload.exp or ngx.time()) - ngx.time()
    if expire_time <= 0 then
        ngx.status = 403
        ngx.say(json_encode({ error = "token has expired" }))
        return
    end

    local response = {
        name = "projects/647037004838/secrets/apisix/versions/1",
        payload = {
          data = "eyJrZXkiOiJ2YWx1ZSJ9",
          dataCrc32c = "2296192492"
        }
      }

    ngx.status = 200
    ngx.say(json_encode(response))
end

function _M.plugin_proxy_rewrite_resp_header()
    ngx.req.read_body()
    local s = "plugin_proxy_rewrite_resp_header"
    ngx.header['Content-Length'] = #s + 1
    ngx.say(s)
end

-- Please add your fake upstream above
function _M.go()
    local action = string.sub(ngx.var.uri, 2)
    action = string.gsub(action, "[/\\.-]", "_")
    if not action or not _M[action] then
        ngx.log(ngx.WARN, "undefined path in test server, uri: ", ngx.var.request_uri)
        return ngx.exit(404)
    end

    inject_headers()
    return _M[action]()
end


function _M.clickhouse_logger_server()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local headers = ngx.req.get_headers()
    ngx.log(ngx.WARN, "clickhouse body: ", data)
    for k, v in pairs(headers) do
        ngx.log(ngx.WARN, "clickhouse headers: " .. k .. ":" .. v)
    end
    ngx.say("ok")
end


function _M.mock_compressed_upstream_response()
    local s = "compressed_response"
    ngx.header['Content-Encoding'] = 'gzip'
    ngx.say(s)
end


return _M
