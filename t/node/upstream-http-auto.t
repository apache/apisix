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
#no_long_string();
no_root_location();
log_level('info');
run_tests;

__DATA__

=== TEST 1: set routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- set route
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/get",
                    "upstream": {
                        "nodes": {
                             "httpbin.org": 1
                        },
                        "type": "roundrobin",
                        "scheme": "http_auto",
                        "pass_host": "node"
                    }
                }]]
            )
            if code > 300 then
               ngy.status(code)
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

=== TEST 2: set ssl
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

            local code, body = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
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

=== TEST 3： http get
--- request
GET /get
--- response_body eval
qr/"url": "http:\/\//
--- no_error_log
[error]

=== TEST 4： https get
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.test.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", sess ~= nil)

            local req = "GET /get HTTP/1.0\r\nHost: www.test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to receive response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- response_body eval
qr/"url": "https:\/\/www.test.com\/get"/
--- no_error_log
[error]
