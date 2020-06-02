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
local json_decode = require("cjson").decode
local json_encode = require("cjson").encode

local _M = {}


function _M.hello()
    ngx.say("hello world")
end

function _M.hello1()
    ngx.say("hello1 world")
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
end

function _M.plugin_proxy_rewrite_args()
    ngx.say("uri: ", ngx.var.uri)
    local args = ngx.req.get_uri_args()
    for k,v in pairs(args) do
        ngx.say(k, ": ", v)
    end
end

function _M.status()
    ngx.say("ok")
end

function _M.sleep1()
    ngx.sleep(1)
    ngx.say("ok")
end

function _M.uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()
    for k, v in pairs(headers) do
        ngx.say(k, ": ", v)
    end
end
_M.uri_plugin_proxy_rewrite = _M.uri
_M.uri_plugin_proxy_rewrite_args = _M.uri

function _M.old_uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()
    for k, v in pairs(headers) do
        ngx.say(k, ": ", v)
    end
end


function _M.opentracing()
    ngx.say("opentracing")
end

function _M.with_header()
    ngx.header['Content-Type'] = 'application/xml'
    ngx.header['X-Server-id'] = 100
    --split into multiple chunk
    ngx.say("hello")
    ngx.say("world")
    ngx.say("!")
end

function _M.mock_skywalking_v2_service_register()
    ngx.say('[{"key":"APISIX","value":1}]')
end

function _M.mock_skywalking_v2_instance_register()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    data = json_decode(data)
    local key = data['instances'][1]['instanceUUID']
    local ret = {}
    ret[1] = {key = key, value = 1}
    ngx.say(json_encode(ret))
end

function _M.mock_skywalking_v2_instance_heartbeat()
    ngx.say('skywalking heartbeat ok')
end

function _M.mock_skywalking_v2_segments()
    ngx.say('skywalking segments ok')
end

function _M.mock_zipkin()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local spans = json_decode(data)
    if #spans < 5 then
        ngx.exit(400)
    end

    for _, span in pairs(spans) do
        if string.sub(span.name, 1, 6) ~= 'apisix' then
            ngx.exit(400)
        end
        if not span.traceId then
            ngx.exit(400)
        end

        if not span.localEndpoint then
            ngx.exit(400)
        end

        if span.localEndpoint.serviceName ~= 'APISIX' and span.localEndpoint.serviceName ~= 'apisix' then
            ngx.exit(400)
        end

        if span.localEndpoint.port ~= 1984 then
            ngx.exit(400)
        end

        if span.localEndpoint.ipv4 ~= ngx.req.get_uri_args()['server_addr'] then
            ngx.exit(400)
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
        ngx.say(json_encode({ok=true, data={ userInfo={nickname="administrator",username="admin", id="100"} }}))
    else
        ngx.status = 401
        ngx.say(json_encode({ok=false, reason="no permission to access"}))
    end
end

function _M.wolf_rbac_user_info()
    local headers = ngx.req.get_headers()
    local token = headers['x-rbac-token']
    if token ~= 'wolf-rbac-token' then
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true, data={ userInfo={nickname="administrator", username="admin", id="100"} }}))
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
    ngx.say('id:' .. headers['X-UserId'] .. ',username:' .. headers['X-Username'] .. ',nickname:' .. headers['X-Nickname'])
end

function _M.websocket_handshake()
    local websocket = require "resty.websocket.server"
    local wb, err = websocket:new()
    if not wb then
        ngx.log(ngx.ERR, "failed to new websocket: ", err)
        return ngx.exit(400)
    end
end
_M.websocket_handshake_route = _M.websocket_handshake

function _M.go()
    local action = string.sub(ngx.var.uri, 2)
    action = string.gsub(action, "[/\\.]", "_")
    if not action or not _M[action] then
        return ngx.exit(404)
    end

    return _M[action]()
end


return _M
