#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set upstream with websocket (id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "enable_websocket": true,
                    "uri": "/websocket_handshake"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: send websocket
--- raw_request eval
"GET /websocket_handshake HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r
Sec-WebSocket-Protocol: chat\r
Sec-WebSocket-Version: 13\r
Origin: http://example.com\r
\r
"
--- response_headers
Upgrade: websocket
Connection: upgrade
Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
Sec-WebSocket-Protocol: chat
!Content-Type
--- raw_response_headers_like: ^HTTP/1.1 101 Switching Protocols\r\n
--- response_body
--- no_error_log
[error]
--- error_code: 101



=== TEST 3: set upstream(id: 6)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/6',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:1981": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: set route with upstream websocket enabled(id: 6)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/6',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/websocket_handshake/route",
                    "enable_websocket": true,
                    "upstream_id": "6"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: send success websocket to upstream
--- raw_request eval
"GET /websocket_handshake/route HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r
Sec-WebSocket-Protocol: chat\r
Sec-WebSocket-Version: 13\r
Origin: http://example.com\r
\r
"
--- response_headers
Upgrade: websocket
Connection: upgrade
Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
Sec-WebSocket-Protocol: chat
!Content-Type
--- raw_response_headers_like: ^HTTP/1.1 101 Switching Protocols\r\n
--- response_body
--- no_error_log
[error]
--- error_code: 101



=== TEST 6: disable websocket(id: 6)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/6',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/websocket_handshake/route",
                    "enable_websocket": false,
                    "upstream_id": "6"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: send websocket to upstream without header support
--- raw_request eval
"GET /websocket_handshake/route HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r
Sec-WebSocket-Protocol: chat\r
Sec-WebSocket-Version: 13\r
Origin: http://example.com\r
\r
"
[error]
--- error_code: 400
--- grep_error_log eval
qr/failed to new websocket: bad "upgrade" request header: nil/
--- grep_error_log_out
