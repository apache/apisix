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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.jwe-decrypt")
            local core = require("apisix.core")
            local conf = {key = "123", secret = "12345678901234567890123456789012"}

            local ok, err = plugin.check_schema(conf, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/{"key":"123","secret":"[a-zA-Z0-9+\\\/]+={0,2}"}/



=== TEST 2: wrong type of key
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwe-decrypt")
            local ok, err = plugin.check_schema({key = 123, secret = "12345678901234567890123456789012"}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "key" validation failed: wrong type: expected string, got number
done



=== TEST 3: wrong type of secret
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwe-decrypt")
            local ok, err = plugin.check_schema({key = "123", secret = 12345678901234567890123456789012}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "secret" validation failed: wrong type: expected string, got number
done



=== TEST 4: secret length too long
--- yaml_config
apisix:
  data_encryption:
    enable_encrypt_fields: false
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwe-decrypt")
            local ok, err = plugin.check_schema({key = "123", secret = "123456789012345678901234567890123"}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
the secret length should be 32 chars
done



=== TEST 5: secret length too long(base64 encode)
--- yaml_config
apisix:
  data_encryption:
    enable_encrypt_fields: false
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.jwe-decrypt")
            local ok, err = plugin.check_schema({key = "123", secret = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXphYmNkZWZn", is_base64_encoded = true}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
the secret length after base64 decode should be 32 chars
done



=== TEST 6: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwe-decrypt": {
                            "key": "user-key",
                            "secret": "12345678901234567890123456789012"
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



=== TEST 7: verify encrypted field
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            -- get plugin conf from etcd, secret and key is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/jack'))
            ngx.say(res.body.node.value.plugins["jwe-decrypt"].key)
            ngx.say(res.body.node.value.plugins["jwe-decrypt"].secret)
        }
    }
--- response_body
XU29sA3FEVF68hGcdPo7sg==
f9pGB0Dt4gYNCLKiINPfVSviKjQs2zfkBCT4+XZ3mDABZkJTr0orzYRD5CptDKMc



=== TEST 8: enable jwe-decrypt plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwe-decrypt": {
                            "header": "Authorization",
                            "forward_header": "Authorization"
                        }
                    },
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



=== TEST 9: create public API route (jwe-decrypt sign)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/jwe/encrypt"
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



=== TEST 10: sign / verify in argument
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, token = t('/apisix/plugin/jwe/encrypt?key=user-key&payload=hello',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            code, err, body = t('/hello',
                ngx.HTTP_GET,
                nil,
                nil,
                { Authorization = token }
            )

            ngx.print(body)
        }
    }
--- response_body
hello world



=== TEST 11: test for unsupported method
--- request
PATCH /apisix/plugin/jwe/encrypt?key=user-key
--- error_code: 404



=== TEST 12: verify, missing token
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"missing JWE token in request"}



=== TEST 13: verify: invalid JWE token
--- request
GET /hello
--- more_headers
Authorization: invalid-eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm02rpOJdg.4nkSYJgwMKYgTeacatgmRw
--- error_code: 400
--- response_body
{"message":"JWE token invalid"}



=== TEST 14: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm02rpOJdg.4nkSYJgwMKYgTeacatgmRw
--- response_body
hello world



=== TEST 15: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm02rpOJdg.4nkSYJgwMKYgTeacatgmRw
--- response_body
hello world



=== TEST 16: verify (header with bearer)
--- request
GET /hello
--- more_headers
Authorization: bearer eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm02rpOJdg.4nkSYJgwMKYgTeacatgmRw
--- response_body
hello world



=== TEST 17: verify (invalid bearer token)
--- request
GET /hello
--- more_headers
Authorization: bearer invalid-eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm02rpOJdg.4nkSYJgwMKYgTeacatgmRw
--- error_code: 400
--- response_body
{"message":"JWE token invalid"}



=== TEST 18: delete a exist consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwe-decrypt": {
                            "key": "user-key",
                            "secret": "12345678901234567890123456789012"
                        }
                    }
                }]]
            )
            ngx.say("code: ", code < 300, " body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "chen",
                    "plugins": {
                        "jwe-decrypt": {
                            "key": "chen-key",
                            "secret": "12345678901234567890123456789021"
                        }
                    }
                }]]
            )
            ngx.say("code: ", code < 300, " body: ", body)

            code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, " body: ", body)

            code, body = t('/apisix/plugin/jwe/encrypt?key=chen-key&payload=hello',
                ngx.HTTP_GET)
            ngx.say("code: ", code < 300, " body: ", body)
        }
    }
--- response_body
code: true body: passed
code: true body: passed
code: true body: passed
code: true body: passed



=== TEST 19: add consumer with username and plugins with base64 secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwe-decrypt": {
                            "key": "user-key",
                            "secret": "fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=",
                            "is_base64_encoded": true
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



=== TEST 20: enable jwt decrypt plugin with base64 secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwe-decrypt": {
                            "header": "Authorization",
                            "forward_header": "Authorization"
                        }
                    },
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



=== TEST 21: create public API route (jwe-decrypt sign)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/jwe/encrypt"
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



=== TEST 22: sign / verify in argument
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, token = t('/apisix/plugin/jwe/encrypt?key=user-key&payload=hello',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            ngx.log(ngx.WARN, "dibag: ", token)

            code, err, body = t('/hello',
                ngx.HTTP_GET,
                nil,
                nil,
                { Authorization = token }
            )

            ngx.print(body)
        }
    }
--- response_body
hello world



=== TEST 23: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body
hello world



=== TEST 24: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body
hello world



=== TEST 25: enable jwt decrypt plugin with test upstream route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwe-decrypt": {
                            "header": "Authorization",
                            "forward_header": "Authorization"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "httpbin.org": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/headers"
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



=== TEST 26:  verify in upstream header
--- request
GET /headers
--- more_headers
Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body_like
.*"Authorization": "hello".*
