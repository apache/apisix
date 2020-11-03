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

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.redirect")
            local ok, err = plugin.check_schema({
                ret_code = 302,
                uri = '/foo',
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: default ret_code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.redirect")
            local ok, err = plugin.check_schema({
                -- ret_code = 302,
                uri = '/foo',
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 3: add plugin with new uri: /test/add
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "/test/add",
                            "ret_code": 301
                        }
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



=== TEST 4: redirect
--- request
GET /hello
--- response_headers
Location: /test/add
--- error_code: 301
--- no_error_log
[error]



=== TEST 5: add plugin with new uri: $uri/test/add
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "$uri/test/add",
                            "ret_code": 301
                        }
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



=== TEST 6: redirect
--- request
GET /hello
--- response_headers
Location: /hello/test/add
--- error_code: 301
--- no_error_log
[error]



=== TEST 7: add plugin with new uri: $uri/test/a${arg_name}c
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "$uri/test/a${arg_name}c",
                            "ret_code": 302
                        }
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



=== TEST 8: redirect
--- request
GET /hello?name=json
--- response_headers
Location: /hello/test/ajsonc
--- error_code: 302
--- no_error_log
[error]



=== TEST 9: add plugin with new uri: /foo$$uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "/foo$$uri",
                            "ret_code": 302
                        }
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



=== TEST 10: redirect
--- request
GET /hello?name=json
--- response_headers
Location: /foo$/hello
--- error_code: 302
--- no_error_log
[error]



=== TEST 11: add plugin with new uri: \\$uri/foo$uri\\$uri/bar
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "\\$uri/foo$uri\\$uri/bar",
                            "ret_code": 301
                        }
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



=== TEST 12: redirect
--- request
GET /hello
--- response_headers
Location: \$uri/foo/hello\$uri/bar
--- error_code: 301
--- no_error_log
[error]



=== TEST 13: add plugin with new uri: $uri/$bad_var/bar
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "$uri/$bad_var/bar",
                            "ret_code": 301
                        }
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



=== TEST 14: redirect
--- request
GET /hello
--- response_headers
Location: /hello//bar
--- error_code: 301
--- no_error_log
[error]



=== TEST 15: http -> https redirect
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "vars": [
                        [
                            "scheme",
                            "==",
                            "http"
                        ]
                    ],
                    "plugins": {
                        "redirect": {
                            "uri": "https://$host$request_uri",
                            "ret_code": 301
                        }
                    }
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



=== TEST 16: redirect
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com/hello



=== TEST 17: enable http_to_https
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "plugins": {
                        "redirect": {
                            "http_to_https": true
                        }
                    }
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



=== TEST 18: redirect
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com/hello



=== TEST 19: enable http_to_https with ret_code(not take effect)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "plugins": {
                        "redirect": {
                            "http_to_https": true,
                            "ret_code": 302
                        }
                    }
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



=== TEST 20: redirect
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com/hello



=== TEST 21: wrong configure, enable http_to_https with uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "plugins": {
                        "redirect": {
                            "http_to_https": true,
                            "uri": "/hello"
                        }
                    }
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
--- error_code: 400
--- response_body eval
qr/error_msg":"failed to check the configuration of plugin redirect err: value should match only one schema, but matches both schemas 1 and 2/
--- no_error_log
[error]



=== TEST 22: enable http_to_https with upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "test.com",
                    "plugins": {
                        "redirect": {
                            "http_to_https": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 23: redirect
--- request
GET /hello
--- more_headers
Host: test.com
--- error_code: 301
--- response_headers
Location: https://test.com/hello



=== TEST 24: set ssl(sni: test.com)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("conf/cert/apisix.crt")
        local ssl_key =  t.read_file("conf/cert/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

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



=== TEST 25: client https request
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

            local sess, err = sock:sslhandshake(nil, "test.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET /hello HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
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
ssl handshake: userdata
sent http request: 58 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Content-Length: 12
received: Connection: close
received: Server: APISIX/\d\.\d+(\.\d+)?
received: Server: \w+
received: \nreceived: hello world
close: 1 nil}
--- no_error_log
[error]
[alert]



=== TEST 26: add plugin with new uri: /test/add
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods":["POST","GET","HEAD"],
                    "plugins": {
                        "redirect": {
                            "http_to_https": true,
                            "ret_code": 307
                        }
                    },
                    "host": "test.com",
                    "uri": "/hello-https"
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



=== TEST 27: http to https post redirect
--- request
POST /hello-https
--- more_headers
Host: test.com
--- response_headers
Location: https://test.com/hello-https
--- error_code: 308
--- no_error_log
[error]



=== TEST 28: http to https get redirect
--- request
GET /hello-https
--- more_headers
Host: test.com
--- response_headers
Location: https://test.com/hello-https
--- error_code: 301
--- no_error_log
[error]



=== TEST 29: http to https head redirect
--- request
HEAD /hello-https
--- more_headers
Host: test.com
--- response_headers
Location: https://test.com/hello-https
--- error_code: 301
--- no_error_log
[error]
