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

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: set upstream (use an id can't be referred by other route
so that we can delete it later)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/upstreams/admin_up',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]],
                [[{
                    "value": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "desc": "new upstream"
                    },
                    "key": "/apisix/upstreams/admin_up"
                }]]
            )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/upstreams/admin_up'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: get upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/admin_up',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "value": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "desc": "new upstream"
                    },
                    "key": "/apisix/upstreams/admin_up"
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



=== TEST 3: delete upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/admin_up', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 4: delete upstream(id: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/upstreams/not_found', ngx.HTTP_DELETE)

            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404



=== TEST 5: push upstream + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message, res = t('/apisix/admin/upstreams',
                 ngx.HTTP_POST,
                 [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                }]],
                [[{
                    "value": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.key, #"/apisix/upstreams/" + 1)
            local res = assert(etcd.get('/upstreams/' .. id))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

            code, message = t('/apisix/admin/upstreams/' .. id, ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed



=== TEST 6: invalid upstream id in uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/invalid_id$',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                }]]
            )

            ngx.exit(code)
        }
    }
--- request
GET /t
--- error_code: 400



=== TEST 7: different id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 3,
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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
{"error_msg":"wrong upstream id"}



=== TEST 8: id in the rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "1",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                }]],
                [[{
                    "value": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "key": "/apisix/upstreams/1"
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



=== TEST 9: integer id less than 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": -100,
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the required"}



=== TEST 10: invalid upstream id: string value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "invalid_id$",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the required"}



=== TEST 11: additional properties is invalid
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin",
                    "_service_name": "xyz",
                    "_discovery_type": "nacos"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid configuration: additional properties forbidden, found .*"\}/



=== TEST 12: set upstream(type: chash)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "key": "remote_addr",
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash"
                }]],
                [[{
                    "value": {
                        "key": "remote_addr",
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash"
                    },
                    "key": "/apisix/upstreams/1"
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



=== TEST 13: unknown type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "unknown"
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



=== TEST 14: invalid weight of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": {
                        "127.0.0.1:8080": "1"
                    },
                    "type": "chash"
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the required"}



=== TEST 15: invalid weight of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                ngx.HTTP_PUT,
                [[{
                    "id": 1,
                    "nodes": {
                        "127.0.0.1:8080": -100
                    },
                    "type": "chash"
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the required"}



=== TEST 16: set upstream (missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "chash"
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
{"error_msg":"missing key"}



=== TEST 17: wrong upstream id, do not need it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_POST,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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
{"error_msg":"wrong upstream id, do not need it"}



=== TEST 18: wrong upstream id, do not need it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                ngx.HTTP_POST,
                [[{
                    "id": 1,
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
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
{"error_msg":"wrong upstream id, do not need it"}



=== TEST 19: client_cert/client_key and client_cert_id cannot appear at the same time
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert_id = 1,
                    client_cert = ssl_cert,
                    client_key = ssl_key
                }
            }
            local code, body = t.test('/apisix/admin/upstreams',
                ngx.HTTP_POST,
                core.json.encode(data)
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/{"error_msg":"invalid configuration: property \\\"tls\\\" validation failed: failed to validate dependent schema for \\\"client_cert|client_key\\\": value wasn't supposed to match schema"}/



=== TEST 20: tls.client_cert_id does not exist
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert_id = 9999999
                }
            }
            local code, body = t.test('/apisix/admin/upstreams',
                ngx.HTTP_POST,
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
{"error_msg":"failed to fetch ssl info by ssl id [9999999], response code: 404"}



=== TEST 21: tls.client_cert_id exist with wrong ssl type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                sni = "test.com",
                cert = ssl_cert,
                key = ssl_key
            }
            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1
                    },
                    tls = {
                        client_cert_id = 1
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to fetch ssl info by ssl id [1], wrong ssl type"}



=== TEST 22: type with default vale
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/upstreams/admin_up',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "desc": "new upstream"
                }]],
                [[{
                    "value": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "desc": "new upstream"
                    },
                    "key": "/apisix/upstreams/admin_up"
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
