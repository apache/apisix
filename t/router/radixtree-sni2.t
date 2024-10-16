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
    $ENV{TEST_ENV_SSL_CRT} = "-----BEGIN CERTIFICATE-----
MIIEsTCCAxmgAwIBAgIUMbgUUCYHkuKDaPy0bzZowlK0JG4wDQYJKoZIhvcNAQEL
BQAwVzELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5nRG9uZzEPMA0GA1UEBwwG
Wmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxEjAQBgNVBAMMCXRlc3QyLmNvbTAgFw0y
MDA0MDQyMjE3NTJaGA8yMTIwMDMxMTIyMTc1MlowVzELMAkGA1UEBhMCQ04xEjAQ
BgNVBAgMCUd1YW5nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVz
dHkxEjAQBgNVBAMMCXRlc3QyLmNvbTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCC
AYoCggGBAMQGBk35V3zaNVDWzEzVGd+EkZnUOrRpXQg5mmcnoKnrQ5rQQMsQCbMO
gFvLt/9OEZQmbE2HuEKsPzL79Yjdu8rGjSoQdbJZ9ccO32uvln1gn68iK79o7Tvm
TCi+BayyNA+lo9IxrBm1wGBkOU1ZPasGYzgBAbMLTSDps1EYxNR8t4l9PrTTRsh6
NZyTYoDeVIsKZ9SckpjWVnxHOkF+AzZzIJJSe2pj572TDLYA/Xw9I4X3L+SHzwTl
iGWNXb2tU367LHERHvensQzdle7mQN2kE5GpB7QPWB+t9V4mn30jc/LyDvOaei6L
+pbl5CriGBTjaR80oXhK765K720BQeKUezri15bQlMaUGQRnzr53ZsqA4PEh6WCX
hUT2ibO32+uZFXzVQw8y/JUkPf76pZagi8DoLV+sfSbUtnpbQ8wyV2qqTM2eCuPi
RgUwXQi2WssKKzrqcgKil3vksHZozLtOmyZiNE4qfNxv+UGoIybJtZmB+9spY0Rw
5zBRuULycQIDAQABo3MwcTAdBgNVHQ4EFgQUCmZefzpizPrb3VbiIDhrA48ypB8w
HwYDVR0jBBgwFoAUCmZefzpizPrb3VbiIDhrA48ypB8wDAYDVR0TBAUwAwEB/zAh
BgNVHREEGjAYggl0ZXN0Mi5jb22CCyoudGVzdDIuY29tMA0GCSqGSIb3DQEBCwUA
A4IBgQA0nRTv1zm1ACugJFfYZfxZ0mLJfRUCFMmFfhy+vGiIu6QtnOFVw/tEOyMa
m78lBiqac15n3YWYiHiC5NFffTZ7XVlOjN2i4x2z2IJsHNa8tU80AX0Q/pizGK/d
+dzlcsGBb9MGT18h/B3/EYQFKLjUsr0zvDb1T0YDlRUsN3Bq6CvZmvfe9F7Yh4Z/
XO5R+rX8w9c9A2jzM5isBw2qp/Ggn5RQodMwApEYkJdu80MuxaY6s3dssS4Ay8wP
VNFEeLcdauJ00ES1OnbnuNiYSiSMOgWBsnR+c8AaSRB/OZLYQQKGGYbq0tspwRjM
MGJRrI/jdKnvJQ8p02abdvA9ZuFChoD3Wg03qQ6bna68ZKPd9peBPpMrDDGDLkGI
NzZ6bLJKILnQkV6b1OHVnPDsKXfXjUTTNK/QLJejTXu9RpMBakYZMzs/SOSDtFlS
A+q25t6+46nvA8msUSBKyOGBX42mJcKvR4OgG44PfDjYfmjn2l+Dz/jNXDclpb+Q
XAzBnfM=
-----END CERTIFICATE-----";
    $ENV{TEST_ENV_SSL_KEY} = "-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----";
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

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

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "*.test2.com"
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

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        ngx.status = code
        ngx.print(body)
    }
}
--- error_code: 400
--- response_body
{"error_msg":"failed to handle cert-key pair[1]: failed to decrypt previous encrypted key"}
--- error_log
decrypt ssl key failed



=== TEST 7: set miss_head ssl certificate
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/incorrect.crt")
        local ssl_key =  t.read_file("t/certs/incorrect.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
            )

        ngx.status = code
        ngx.print(body)
    }
}
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
--- response_body
failed to do SSL handshake: handshake failed
--- error_log
failed to find SNI: please check if the client requests via IP or uses an outdated protocol
--- no_error_log
[alert]



=== TEST 9: client request without sni, but fallback_sni is set
--- yaml_config
apisix:
  node_listen: 1984
  ssl:
    fallback_sni: "a.test2.com"
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

            local sess, err = sock:sslhandshake(nil, nil, false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 10: set sni with uppercase
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "*.TesT2.com"}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 11: match case insensitive
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

            local sess, err = sock:sslhandshake(nil, "a.test2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 12: set snis with uppercase
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, snis = {"TesT2.com", "a.com"}}

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 13: match case insensitive
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

            local sess, err = sock:sslhandshake(nil, "TEST2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 14: ensure table is reused in TLS handshake
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

            local sess, err = sock:sslhandshake(nil, "TEST2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- extra_init_by_lua
    local tablepool = require("apisix.core").tablepool
    local old_fetch = tablepool.fetch
    tablepool.fetch = function(name, ...)
        ngx.log(ngx.WARN, "fetch table ", name)
        return old_fetch(name, ...)
    end

    local old_release = tablepool.release
    tablepool.release = function(name, ...)
        ngx.log(ngx.WARN, "release table ", name)
        return old_release(name, ...)
    end
--- response_body
ssl handshake: true
--- grep_error_log eval
qr/(fetch|release) table \w+/
--- grep_error_log_out
fetch table api_ctx
release table api_ctx



=== TEST 15: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/ssl test2.com.crt=@t/certs/test2.crt test2.com.key=@t/certs/test2.key
--- response_body
Success! Data written to: kv/apisix/ssl



=== TEST 16: set ssl conf with secret ref: vault
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix": "kv/apisix",
                    "token" : "root"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            -- set ssl
            local code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$secret://vault/test1/ssl/test2.com.crt",
                    "key": "$secret://vault/test1/ssl/test2.com.key",
                    "sni": "test2.com"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 17: get cert and key from vault
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

            local sess, err = sock:sslhandshake(nil, "test2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 18: set ssl conf with secret ref: env
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- set ssl
            local code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$env://TEST_ENV_SSL_CRT",
                    "key": "$env://TEST_ENV_SSL_KEY",
                    "sni": "test2.com"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 19: get cert and key from env
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

            local sess, err = sock:sslhandshake(nil, "test2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 20: set ssl conf with secret ref: only cert use env
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            -- set ssl
            local ssl_key =  t.read_file("t/certs/test2.key")
            local data = {
                cert = "$env://TEST_ENV_SSL_CRT",
                key = ssl_key,
                sni = "TesT2.com"
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 21: get cert from env
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

            local sess, err = sock:sslhandshake(nil, "test2.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true



=== TEST 22: set ssl conf with secret ref: ENV
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- set ssl
            local code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$ENV://TEST_ENV_SSL_CRT",
                    "key": "$ENV://TEST_ENV_SSL_KEY",
                    "sni": "test3.com"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 23: verify ssl after set with secret ref: ENV
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

            local sess, err = sock:sslhandshake(nil, "test3.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            ngx.say("ssl handshake: ", sess ~= nil)
        end  -- do
        -- collectgarbage()
    }
}
--- response_body
ssl handshake: true
