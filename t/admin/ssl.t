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
