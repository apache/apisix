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

no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.csrf")
            local ok, err = plugin.check_schema({name = '_csrf', expires = 3600, key = 'testkey'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: set csrf plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "csrf": {
                            "key": "userkey",
                            "expires": 1000000000
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
--- response_body
passed



=== TEST 3: have csrf cookie
--- request
GET /hello
--- response_headers_like
Set-Cookie: apisix-csrf-token\s*=\s*[^;]+(.*)?$



=== TEST 4: block request
--- request
POST /hello
--- error_code: 401
--- response_body
{"error_msg":"no csrf token in headers"}



=== TEST 5: only header
--- request
POST /hello
--- more_headers
apisix-csrf-token: wrongtoken
--- error_code: 401
--- response_body
{"error_msg":"no csrf cookie"}



=== TEST 6: only cookie
--- request
POST /hello
--- more_headers
Cookie: apisix-csrf-token=testcookie
--- error_code: 401
--- response_body
{"error_msg":"no csrf token in headers"}



=== TEST 7: header and cookie mismatch
--- request
POST /hello
--- more_headers
apisix-csrf-token: wrongtoken
Cookie: apisix-csrf-token=testcookie
--- error_code: 401
--- response_body
{"error_msg":"csrf token mismatch"}



=== TEST 8: invalid csrf token
--- request
POST /hello
--- more_headers
apisix-csrf-token: eyJyYW5kb20iOjAuMTYwOTgzMDYwMTg0NDksInNpZ24iOiI2YTEyYmViYTI4MzAyNDg4MDRmNGU0N2VkZDY5MWFmNjg5N2IyNzQ4YTY1YWMwMDJiMGFjMzFlN2NlMDdlZTViIiwiZXhwaXJlcyI6MTc0MzExOTkxMX0=
Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuMTYwOTgzMDYwMTg0NDksInNpZ24iOiI2YTEyYmViYTI4MzAyNDg4MDRmNGU0N2VkZDY5MWFmNjg5N2IyNzQ4YTY1YWMwMDJiMGFjMzFlN2NlMDdlZTViIiwiZXhwaXJlcyI6MTc0MzExOTkxMX0=
--- error_code: 401
--- error_log: Invalid signatures
--- response_body
{"error_msg":"Failed to verify the csrf token signature"}



=== TEST 9: valid csrf token
--- request
POST /hello
--- more_headers
apisix-csrf-token: eyJyYW5kb20iOjAuNDI5ODYzMTk3MTYxMzksInNpZ24iOiI0ODRlMDY4NTkxMWQ5NmJhMDc5YzQ1ZGI0OTE2NmZkYjQ0ODhjODVkNWQ0NmE1Y2FhM2UwMmFhZDliNjE5OTQ2IiwiZXhwaXJlcyI6MjY0MzExOTYyNH0=
Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNDI5ODYzMTk3MTYxMzksInNpZ24iOiI0ODRlMDY4NTkxMWQ5NmJhMDc5YzQ1ZGI0OTE2NmZkYjQ0ODhjODVkNWQ0NmE1Y2FhM2UwMmFhZDliNjE5OTQ2IiwiZXhwaXJlcyI6MjY0MzExOTYyNH0=



=== TEST 10: change expired
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "csrf": {
                            "key": "userkey",
                            "expires": 1
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
--- response_body
passed



=== TEST 11: expired csrf token
--- request
POST /hello
--- more_headers
apisix-csrf-token: eyJyYW5kb20iOjAuMDY3NjAxMDQwMDM5MzI4LCJzaWduIjoiOTE1Yjg2MjBhNTg1N2FjZmIzNjIxOTNhYWVlN2RkYjY5NmM0NWYwZjE5YjY5Zjg3NjM4ZTllNGNjNjYxYjQwNiIsImV4cGlyZXMiOjE2NDMxMjAxOTN9
Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuMDY3NjAxMDQwMDM5MzI4LCJzaWduIjoiOTE1Yjg2MjBhNTg1N2FjZmIzNjIxOTNhYWVlN2RkYjY5NmM0NWYwZjE5YjY5Zjg3NjM4ZTllNGNjNjYxYjQwNiIsImV4cGlyZXMiOjE2NDMxMjAxOTN9
--- error_code: 401
--- error_log: token has expired



=== TEST 12: token has expired after sleep 2s
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end
            local cookie = res.headers["Set-Cookie"]
            local token = cookie:match("=([^;]+)")

            ngx.sleep(2)

            local res, err = httpc:request_uri(uri, {
                method = "POST",
                headers = {
                    ["apisix-csrf-token"] = token,
                    ["Cookie"] = cookie,
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            if res.status >= 300 then
                ngx.status = res.status
            end
        }
    }
--- error_code: 401
--- error_log: token has expired



=== TEST 13: set expires 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "csrf": {
                            "key": "userkey",
                            "expires": 0
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
--- response_body
passed



=== TEST 14: token no expired after sleep 1s
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.sleep(1)

            local cookie = res.headers["Set-Cookie"]
            local token = cookie:match("=([^;]+)")

            local res, err = httpc:request_uri(uri, {
                method = "POST",
                headers = {
                    ["apisix-csrf-token"] = token,
                    ["Cookie"] = cookie,
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            if res.status >= 300 then
                ngx.status = res.status
            end
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- response_body
hello world



=== TEST 15: data encryption for key
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "csrf": {
                            "key": "userkey",
                            "expires": 1000000000
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["csrf"].key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["csrf"].key)
        }
    }
--- response_body
userkey
mt39FazQccyMqt4ctoRV7w==
