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
--- no_error_log
12345678901234567890123456789012



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
--- no_error_log
12345678901234567890123456789012



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
--- no_error_log
12345678901234567890123456789012



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
--- no_error_log
123456789012345678901234567890123



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
--- no_error_log
YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXphYmNkZWZn



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
--- no_error_log
12345678901234567890123456789012



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
--- no_error_log
12345678901234567890123456789012



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
--- no_error_log
12345678901234567890123456789012



=== TEST 9: verify, missing token
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"missing JWE token in request"}



=== TEST 10: verify: invalid JWE token
--- request
GET /hello
--- more_headers
Authorization: invalid-eyJraWQiOiJ1c2VyLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm0.rNt131nG5wMvUD1KXbwLGA
--- error_code: 400
--- response_body
{"message":"JWE token invalid"}



=== TEST 11: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJraWQiOiJ1c2VyLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm0.rNt131nG5wMvUD1KXbwLGA
--- response_body
hello world



=== TEST 12: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJraWQiOiJ1c2VyLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm0.rNt131nG5wMvUD1KXbwLGA
--- response_body
hello world



=== TEST 13: verify (header with bearer)
--- request
GET /hello
--- more_headers
Authorization: bearer eyJraWQiOiJ1c2VyLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm0.rNt131nG5wMvUD1KXbwLGA
--- response_body
hello world



=== TEST 14: verify (invalid bearer token)
--- request
GET /hello
--- more_headers
Authorization: bearer invalid-eyJraWQiOiJ1c2VyLWtleSIsImFsZyI6ImRpciIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy.6JeRgm0.rNt131nG5wMvUD1KXbwLGA
--- error_code: 400
--- response_body
{"message":"JWE token invalid"}



=== TEST 15: delete a exist consumer
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

            -- the remaining consumer can still be verified
            local chen_token = "eyJhbGciOiJkaXIiLCJraWQiOiJjaGVuLWtleSIsImVuYyI6IkEyNTZHQ00ifQ"
                .. "..MTIzNDU2Nzg5MDEy.ar0vE2I.AOndbhR7J1e2oM3N2c-KYQ"
            code, body = t('/hello',
                ngx.HTTP_GET,
                nil,
                nil,
                { Authorization = chen_token })
            ngx.say("code: ", code < 300, " body: ", body)
        }
    }
--- response_body
code: true body: passed
code: true body: passed
code: true body: passed
code: true body: passed
--- no_error_log
12345678901234567890123456789012
12345678901234567890123456789021



=== TEST 16: add consumer with username and plugins with base64 secret
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
--- no_error_log
fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=



=== TEST 17: enable jwt decrypt plugin with base64 secret
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
--- no_error_log
fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=



=== TEST 18: verify (in header)
--- request
GET /hello
--- more_headers
Authorization: Bearer eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body
hello world
--- no_error_log
fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=



=== TEST 19: verify (in header without Bearer)
--- request
GET /hello
--- more_headers
Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body
hello world



=== TEST 20: enable jwt decrypt plugin with test upstream route
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
                            "httpbin.local:8280": 1
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
--- no_error_log
fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=



=== TEST 21:  verify in upstream header
--- request
GET /headers
--- more_headers
Authorization: eyJhbGciOiJkaXIiLCJraWQiOiJ1c2VyLWtleSIsImVuYyI6IkEyNTZHQ00ifQ..MTIzNDU2Nzg5MDEy._0DrWD0.vl-ydutnNuMpkYskwNqu-Q
--- response_body_like
.*"Authorization": "hello".*
--- no_error_log
fo4XKdZ1xSrIZyms4q2BwPrW5lMpls9qqy5tiAk2esc=



=== TEST 27: setup route protected by jwe-decrypt
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jwe_fail_user",
                    "plugins": {
                        "jwe-decrypt": {
                            "key": "jwe-fail-key",
                            "secret": "12345678901234567890123456789012"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to add consumer")
                return
            end

            code = t('/apisix/admin/routes/10',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwe-decrypt": {
                            "header": "Authorization",
                            "forward_header": "Authorization"
                        },
                        "proxy-rewrite": {
                            "uri": "/hello"
                        }
                    },
                    "upstream": {
                        "nodes": { "127.0.0.1:1980": 1 },
                        "type": "roundrobin"
                    },
                    "uri": "/jwe-decrypt-fail"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 28: well-formed token whose ciphertext does not decrypt is rejected
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local enc = require("ngx.base64").encode_base64url

            -- a structurally valid JWE whose ciphertext and tag were not
            -- produced with the consumer secret, so AES-256-GCM verification
            -- fails when the plugin tries to decrypt it
            local header = enc(core.json.encode({
                alg = "dir", enc = "A256GCM", kid = "jwe-fail-key",
            }))
            local token = header .. ".." .. enc("123456789012") .. "."
                          .. enc("undecryptable") .. "." .. enc("0123456789abcdef")

            local code = t('/jwe-decrypt-fail', ngx.HTTP_GET, nil, nil,
                           { Authorization = "Bearer " .. token })
            ngx.say("status: ", code)
        }
    }
--- response_body
status: 400
