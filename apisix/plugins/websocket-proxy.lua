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


-- "client"/"upstream" here name the same two roles resty.websocket.proxy
-- itself uses: "client" is the side facing the real downstream WebSocket
-- client, "upstream" is the side facing the backend. Left unset, the
-- library defaults max_payload_len (and, through it, the max size of a
-- single unfragmented frame) to 65535 on both sides.
--
-- 2147483647 (0x7fffffff) is api7-lua-resty-websocket's own hard ceiling:
-- protocol.lua's send_frame() only encodes a 31-bit length and refuses to
-- send anything past it ("payload too big"), so a configured value beyond
-- this bound would pass schema validation but could never actually be
-- honored end to end.
local MAX_PAYLOAD_LEN_CEILING = 2147483647

local schema = {
    type = "object",
    properties = {
        client_max_payload_len = {
            type = "integer",
            minimum = 1,
            maximum = MAX_PAYLOAD_LEN_CEILING,
            description = "max size, in bytes, of a single WebSocket " ..
                "message this route will accept from the downstream client",
        },
        upstream_max_payload_len = {
            type = "integer",
            minimum = 1,
            maximum = MAX_PAYLOAD_LEN_CEILING,
            description = "max size, in bytes, of a single WebSocket " ..
                "message this route will accept from the upstream",
        },
    },
}


local _M = {
    version = 0.1,
    priority = 507,
    name = "websocket-proxy",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.ws_handshake(conf, ctx)
    ctx.websocket_proxy_client_max_payload_len = conf.client_max_payload_len
    ctx.websocket_proxy_upstream_max_payload_len = conf.upstream_max_payload_len
end


return _M
