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

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

run_tests;

__DATA__

=== TEST 1 set ssl with multiple certificates.
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key = t.read_file("t/certs/apisix.key")
        local ssl_ecc_cert = t.read_file("t/certs/apisix_ecc.crt")
        local ssl_ecc_key = t.read_file("t/certs/apisix_ecc.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            certs = { ssl_ecc_cert },
            keys = { ssl_ecc_key },
            sni = "test.com",
        }

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
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
--- no_error_log
[error]



=== TEST 2: client request using ECC certificate
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
location /t {
    lua_ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384;
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

            local sess, err = sock:sslhandshake(nil, "test.com", false)
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
connected: 1
ssl handshake: true



=== TEST 3: client request using RSA certificate
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    lua_ssl_ciphers ECDHE-RSA-AES256-SHA384;
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

            local sess, err = sock:sslhandshake(nil, "test.com", false)
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
connected: 1
ssl handshake: true



=== TEST 4: set ssl(sni: *.test2.com) once again
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "*.test2.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "*.test2.com"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
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
--- no_error_log
[error]



=== TEST 5: caching of parsed certs and pkeys
--- config
listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        local work = function()
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.test2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do

        work()
        work()

        -- collectgarbage()
    }
}
--- request
GET /t
--- response_body eval
qr{connected: 1
ssl handshake: true
close: 1 nil
connected: 1
ssl handshake: true
close: 1 nil}
--- grep_error_log eval
qr/parsing (cert|(priv key)) for sni: www.test2.com/
--- grep_error_log_out
parsing cert for sni: www.test2.com
parsing priv key for sni: www.test2.com



=== TEST 6: set ssl(encrypt ssl keys with another iv)
--- config
location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local raw_ssl_key = t.read_file("t/certs/test2.key")
        local ssl_key = t.aes_encrypt(raw_ssl_key)
        local data = {
            certs = { ssl_cert },
            keys = { ssl_key },
            snis = {"test2.com", "*.test2.com"},
            cert = ssl_cert,
            key = raw_ssl_key,
        }

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
            )

        ngx.status = code
        ngx.print(body)
    }
}
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to handle cert-key pair[1]: failed to decrypt previous encrypted key"}



=== TEST 7: set miss_head ssl certificate
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/incorrect.crt")
        local ssl_key =  t.read_file("t/certs/incorrect.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
            )

        ngx.status = code
        ngx.print(body)
    }
}
--- request
GET /t
--- response_body
{"error_msg":"failed to parse cert: PEM_read_bio_X509_AUX() failed"}
--- error_code: 400
--- no_error_log
[alert]



=== TEST 8: client request without sni
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

            local sess, err = sock:sslhandshake(nil, nil, true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- response_body
failed to do SSL handshake: handshake failed
--- error_log
failed to fetch ssl config: failed to find SNI: please check if the client requests via IP or uses an outdated protocol
--- no_error_log
[alert]
