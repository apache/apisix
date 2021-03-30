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

no_root_location();

run_tests();

__DATA__

=== TEST 1: set route: remote addr = ::1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "remote_addr": "::1",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 2: IPv6 /not_found
--- listen_ipv6
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.2)
        local t = require("lib.test_admin").test_ipv6
        t('/not_found')
    }
}
--- request
GET /t
--- response_body eval
qr/"error_msg":"404 Route Not Found"/
--- no_error_log
[error]



=== TEST 3: IPv4 /not_found
--- listen_ipv6
--- request
GET /not_found
--- error_code: 404
--- response_body eval
qr/"error_msg":"404 Route Not Found"/
--- no_error_log
[error]



=== TEST 4: IPv6 /hello
--- listen_ipv6
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.2)
        local t = require("lib.test_admin").test_ipv6
        t('/hello')
    }
}
--- request
GET /t
--- response_body eval
qr{connected: 1
request sent: 59
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Content-Length: 12
received: Connection: close
received: Server: APISIX/\d\.\d+(\.\d+)?
received: 
received: hello world
failed to receive a line: closed \[\]
close: 1 nil}
--- no_error_log
[error]



=== TEST 5: IPv4 /hello
--- listen_ipv6
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]
