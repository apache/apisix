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

run_tests;

__DATA__

=== TEST 1: set ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local etcd = require("apisix.core.etcd")
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

            local res = assert(etcd.get('/ssls/1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: get ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_GET,
                nil,
                [[{
                    "value": {
                        "sni": "test.com",
                        "key": null
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



=== TEST 3: delete ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/ssls/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 4: delete ssl(id: 99999999999999)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/ssls/99999999999999', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404



=== TEST 5: push ssl + delete
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "foo.com"}

            local code, message, res = t.test('/apisix/admin/ssls',
                ngx.HTTP_POST,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "foo.com"
                    }
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.key, #"/apisix/ssls/" + 1)
            code, message = t.test('/apisix/admin/ssls/' .. id, ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed



=== TEST 6: missing certificate information
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {sni = "foo.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "foo.com"
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: then clause did not match"}



=== TEST 7: wildcard host name
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "*.foo.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "*.foo.com"
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



=== TEST 8: store sni in `snis`
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                cert = ssl_cert, key = ssl_key,
                snis = {"*.foo.com", "bar.com"},
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "snis": ["*.foo.com", "bar.com"]
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



=== TEST 9: string id
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code > 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: string id(delete)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/a-b-c-ABC_0123',
                ngx.HTTP_DELETE
            )
            if code > 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 11: invalid id
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/*invalid',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code > 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400



=== TEST 12: set ssl with multicerts(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local ssl_ecc_cert = t.read_file("t/certs/apisix_ecc.crt")
            local ssl_ecc_key = t.read_file("t/certs/apisix_ecc.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                certs = {ssl_ecc_cert},
                keys = {ssl_ecc_key}
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
--- request
GET /t
--- response_body
passed



=== TEST 13: mismatched certs and keys
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_ecc_cert = t.read_file("t/certs/apisix_ecc.crt")

            local data = {
                sni = "test.com",
                certs = { ssl_ecc_cert },
                keys = {},
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: then clause did not match"}



=== TEST 14: set ssl(with labels)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com", labels = { version = "v2", build = "16", env = "production"}}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "labels": {
                            "version": "v2",
                            "build": "16",
                            "env": "production"
                        }
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



=== TEST 15: invalid format of label value: set ssl
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com", labels = { env = {"production", "release"}}}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "labels": {
                            "env": ["production", "release"]
                        }
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"labels\" validation failed: failed to validate env (matching \".*\"): wrong type: expected string, got table"}



=== TEST 16: create ssl with manage fields(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 17: delete test ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/ssls/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 18: create/patch ssl
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local etcd = require("apisix.core.etcd")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body, res = t.test('/apisix/admin/ssls',
                ngx.HTTP_POST,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
                    }
                }]]
            )

            if code ~= 200 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local id = string.sub(res.key, #"/apisix/ssls/" + 1)
            local res = assert(etcd.get('/ssls/' .. id))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

            local code, body = t.test('/apisix/admin/ssls/' .. id,
                ngx.HTTP_PATCH,
                core.json.encode({create_time = 0, update_time = 1})
            )

            if code ~= 200 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local res = assert(etcd.get('/ssls/' .. id))
            local create_time = res.body.node.value.create_time
            assert(create_time == 0, "create_time mismatched")
            local update_time = res.body.node.value.update_time
            assert(update_time == 1, "update_time mismatched")

            -- clean up
            local code, body = t.test('/apisix/admin/ssls/' .. id, ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 19: missing sni information
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: then clause did not match"}



=== TEST 20: type client, missing sni information
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {type = "client", cert = ssl_cert, key = ssl_key}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- response_body chomp
passed



=== TEST 21: set ssl with sercret
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                sni = "test.com",
                cert = "$secret://vault/test/ssl/test.com.crt",
                key = "$secret://vault/test/ssl/test.com.key",
                certs = {"$secret://vault/test/ssl/test.com.2.crt"},
                keys = {"$secret://vault/test/ssl/test.com.2.key"}
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "cert": "$secret://vault/test/ssl/test.com.crt",
                        "key": "$secret://vault/test/ssl/test.com.key",
                        "certs": ["$secret://vault/test/ssl/test.com.2.crt"],
                        "keys": ["$secret://vault/test/ssl/test.com.2.key"]
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



=== TEST 22: set ssl with env, and prefix is all uppercase or lowercase
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                sni = "test.com",
                cert = "$ENV://APISIX_TEST_SSL_CERT",
                key = "$env://APISIX_TEST_SSL_KEY",
                certs = {"$env://APISIX_TEST_SSL_CERTS"},
                keys = {"$ENV://APISIX_TEST_SSL_KEYS"},
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "cert": "$ENV://APISIX_TEST_SSL_CERT",
                        "key": "$env://APISIX_TEST_SSL_KEY",
                        "certs": ["$env://APISIX_TEST_SSL_CERTS"],
                        "keys": ["$ENV://APISIX_TEST_SSL_KEYS"]
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



=== TEST 23: set ssl with invalid prefix
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                sni = "test.com",
                cert = "$ENV://APISIX_TEST_SSL_CERT",
                key = "$env://APISIX_TEST_SSL_KEY",
                certs = {"https://APISIX_TEST_SSL_CERTS"},
                keys = {"$ENV://APISIX_TEST_SSL_KEYS"},
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"certs\" validation failed: failed to validate item 1: string too short, expected at least 128, got 29"}



=== TEST 24: GET single SSL returns certificate validity and omits private keys
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local ssl_ecc_cert = t.read_file("t/certs/apisix_ecc.crt")
            local ssl_ecc_key = t.read_file("t/certs/apisix_ecc.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                certs = {ssl_ecc_cert},
                keys = {ssl_ecc_key},
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code ~= 200 and code ~= 201 then
                ngx.say("PUT failed: ", code, " ", body)
                return
            end

            local code2, _, raw_body2 = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_GET
            )
            if code2 ~= 200 then
                ngx.say("GET failed: ", code2)
                return
            end

            local res_data = core.json.decode(raw_body2)
            local value = res_data and res_data.value
            if value == nil then
                ngx.say("no value in response, body: ", raw_body2)
                return
            end

            if value.key ~= nil then
                ngx.say("FAIL: key field not stripped, type: ", type(value.key))
                return
            end

            if value.keys ~= nil then
                local keys_count = type(value.keys) == "table" and #value.keys or "n/a"
                ngx.say("FAIL: keys field not stripped, type: ", type(value.keys),
                        ", count: ", keys_count)
                return
            end

            assert(value.validity_start == 1561414685, "unexpected primary validity_start")
            assert(value.validity_end == 4715014685, "unexpected primary validity_end")
            assert(#value.certs_validity == 1, "unexpected additional certificate count")
            assert(value.certs_validity[1].validity_start == 1597739077)
            assert(value.certs_validity[1].validity_end == 1629275077)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 25: GET SSL list returns certificate validity and omits private keys
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            -- TEST 24 already created ssls/1 with multicerts; rely on test ordering
            local code2, _, raw_body2 = t.test('/apisix/admin/ssls',
                ngx.HTTP_GET
            )
            if code2 ~= 200 then
                ngx.say("GET list failed: ", code2)
                return
            end

            local res_data = core.json.decode(raw_body2)
            local list = res_data and res_data.list
            if list == nil or #list == 0 then
                ngx.say("FAIL: empty list")
                return
            end

            local found = false
            for i, item in ipairs(list) do
                local value = item.value
                if value then
                    if value.key ~= nil then
                        ngx.say("FAIL: item ", i, " key field not stripped")
                        return
                    end
                    if value.keys ~= nil then
                        ngx.say("FAIL: item ", i, " keys field not stripped")
                        return
                    end
                    if value.id == "1" then
                        found = true
                        assert(value.validity_start == 1561414685)
                        assert(value.validity_end == 4715014685)
                        assert(#value.certs_validity == 1)
                        assert(value.certs_validity[1].validity_start == 1597739077)
                        assert(value.certs_validity[1].validity_end == 1629275077)
                    end
                end
            end
            assert(found, "SSL resource missing from list")

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 26: cleanup ssl created in TEST 24
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/ssls/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 27: GET SSL derives updated leaf dates and keeps positions for certificate references
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local cert = t.read_file("t/certs/apisix.crt")
            local key = t.read_file("t/certs/apisix.key")
            local ecc_cert = t.read_file("t/certs/apisix_ecc.crt")
            local ecc_key = t.read_file("t/certs/apisix_ecc.key")
            local ref = "$ENV://SSL_VALIDITY_TEST_" .. string.rep("X", 128)
            local uri = "/apisix/admin/ssls/validity"
            local conf = {sni = "test.com", cert = ref, key = ref}

            local code, err = t.test(uri, ngx.HTTP_PUT, conf)
            assert(code == 200 or code == 201, err)
            local status, _, body = t.test(uri, ngx.HTTP_GET)
            assert(status == 200)
            local value = core.json.decode(body).value
            assert(value.cert == ref and value.validity_start == nil and value.validity_end == nil)

            conf.cert = ecc_cert .. cert
            conf.key = ecc_key
            conf.certs = {ref, cert}
            conf.keys = {ref, key}
            code, err = t.test(uri, ngx.HTTP_PUT, conf)
            assert(code == 200 or code == 201, err)

            status, _, body = t.test(uri, ngx.HTTP_GET)
            assert(status == 200)
            value = core.json.decode(body).value
            assert(value.validity_start == 1597739077 and value.validity_end == 1629275077)
            assert(value.certs_validity[1] == ngx.null)
            assert(value.certs_validity[2].validity_start == 1561414685)
            assert(value.certs_validity[2].validity_end == 4715014685)

            local res = assert(core.etcd.get("/ssls/validity"))
            local stored = res.body.node.value
            assert(stored.validity_start == nil and stored.validity_end == nil)
            assert(stored.certs_validity == nil)

            assert(t.test(uri, ngx.HTTP_DELETE) == 200)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed


=== TEST 28: reject mismatched SSL keys on create and patch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local uri = "/apisix/admin/ssls/key-pair-check"
            local conf = {
                sni = "match.example.com",
                cert = t.read_file("t/certs/apisix.crt"),
                key = t.read_file("t/certs/test2.key"),
            }
            local code, _, body = t.test(uri, ngx.HTTP_PUT, conf)
            assert(code == 400 and body:find("certificate and private key do not match", 1, true))

            conf.key = t.read_file("t/certs/apisix.key")
            local ecc_key = t.read_file("t/certs/apisix_ecc.key")
            conf.certs = {t.read_file("t/certs/apisix_ecc.crt")}
            conf.keys = {ecc_key}
            assert(t.test(uri, ngx.HTTP_PUT, conf) == 201)

            code, _, body = t.test(uri, ngx.HTTP_PATCH, {keys = {conf.key}})
            assert(code == 400 and body:find("cert-key pair[1]", 1, true))
            code, _, body = t.test(uri, ngx.HTTP_PATCH, {key = ecc_key})
            assert(code == 400 and body:find("certificate and private key do not match", 1, true))

            -- The expired additional certificate is allowed and survives the failed patch.
            assert(t.test(uri, ngx.HTTP_PATCH, {status = 0}) == 200)
            assert(t.test(uri, ngx.HTTP_DELETE) == 200)
            ngx.say("checked")
        }
    }
--- request
GET /t
--- response_body
checked
--- no_error_log
[error]
