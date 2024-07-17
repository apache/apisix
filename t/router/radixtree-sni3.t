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

log_level('debug');
no_root_location();

BEGIN {
    $ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});


run_tests;

__DATA__

=== TEST 1: set sni with trailing period
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "*.test.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed
--- error_code: 201



=== TEST 2: match against sni with no trailing period
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local sess, err = sock:sslhandshake(nil, "a.test.com.", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- response_body
ssl handshake: true



=== TEST 3: set snis with trailing period
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, snis = {"test2.com", "a.com"}}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 4: match agains sni with no trailing period
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local sess, err = sock:sslhandshake(nil, "test2.com.", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- response_body
ssl handshake: true



=== TEST 5: set ssl(sni: www.test.com.)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local ssl_cert = t.read_file("t/certs/test-dot.crt")
        local ssl_key =  t.read_file("t/certs/test-dot.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com."}
        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "www.test.com."
                },
                "key": "/apisix/ssls/1"
            }]]
        )
        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 6: set route(id: 1)
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



=== TEST 7: client request
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
            local sess, err = sock:sslhandshake(nil, "www.test.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
            local req = "GET /hello HTTP/1.0\r\nHost: www.test.com\r\nConnection: close\r\n\r\n"
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
qr{connected: 1
ssl handshake: true
sent http request: 62 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Content-Length: 12
received: Connection: close
received: Server: APISIX/\d\.\d+(\.\d+)?
received: \nreceived: hello world
close: 1 nil}
--- error_log
server name: "www.test.com"
--- no_error_log
[error]
[alert]
