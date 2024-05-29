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

add_block_preprocessor( sub{
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $TEST_NGINX_HTML_DIR ||= html_dir();

    my $config = <<_EOC_;
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
                sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                sess, err = sock:sslhandshake(nil, "www.test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end
            end

            ngx.say("ssl handshake: ", sess ~= nil)

            local req = "GET /hello HTTP/1.0\\r\\nHost: www.test.com\\r\\nConnection: close\\r\\n\\r\\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
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
_EOC_

   if (!$block->config) {
       $block->set_value("config", $config)
   }
}

);


run_tests;

__DATA__

=== TEST 1: set ssl(sni: www.test.com), encrypt with the first keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - edd1c9f0985e76a1
            - qeddd145sfvddff3
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "www.test.com"
                },
                "key": "/apisix/ssls/1"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 2: set route(id: 1)
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: "edd1c9f0985e76a1"
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
--- response_body
passed



=== TEST 3: client request with the old style keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: "edd1c9f0985e76a1"
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



=== TEST 4: client request with the new style keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - edd1c9f0985e76a1
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



=== TEST 5: client request failed with the wrong keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - qeddd145sfvddff3
--- error_log
decrypt ssl key failed
[alert]



=== TEST 6: client request successfully, use the two keyring to decrypt in turn
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - qeddd145sfvddff3
            - edd1c9f0985e76a1
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
--- ignore_error_log



=== TEST 7: remove test ssl certs
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - edd1c9f0985e76a1
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        t.test('/apisix/admin/ssls/1', ngx.HTTP_DELETE)
    }
}



=== TEST 8: set ssl(sni: www.test.com), do not encrypt
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: null
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "www.test.com"
                },
                "key": "/apisix/ssls/1"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 9: client request without keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: null
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



=== TEST 10: remove test ssl certs
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: null
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        t.test('/apisix/admin/ssls/1', ngx.HTTP_DELETE)
    }
}



=== TEST 11: set ssl(sni: www.test.com) with long label
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring: null
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com",
                      labels = {secret = "js-design-test-bigdata-data-app-service-router-my-secret-number-123456"}}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "www.test.com",
                    "labels": {
                        "secret": "js-design-test-bigdata-data-app-service-router-my-secret-number-123456"
                    },
                },
                "key": "/apisix/ssls/1"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 12: set ssl(sni: www.test.com), encrypt with the first keyring
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - edd1c9f0985e76a1
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "test.com"
                },
                "key": "/apisix/ssls/1"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 13: update encrypt keyring, and set ssl(sni: test2.com)
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - qeddd145sfvddff3
            - edd1c9f0985e76a1
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test2.com"}

        local code, body = t.test('/apisix/admin/ssls/2',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "test2.com"
                },
                "key": "/apisix/ssls/2"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 14: Successfully access test.com
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - qeddd145sfvddff3
            - edd1c9f0985e76a1
--- exec
curl -k -s --resolve "test2.com:1994:127.0.0.1" https://test2.com:1994/hello 2>&1 | cat
--- response_body
hello world



=== TEST 15: Successfully access test2.com
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        keyring:
            - qeddd145sfvddff3
            - edd1c9f0985e76a1
--- exec
curl -k -s --resolve "test2.com:1994:127.0.0.1" https://test2.com:1994/hello 2>&1 | cat
--- response_body
hello world
