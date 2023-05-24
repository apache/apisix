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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: PUT
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:12800/get",
                    "prefix" : "apisix",
                    "token" : "apisix"
                }]],
                [[{
                    "value": {
                        "uri": "http://127.0.0.1:12800/get",
                        "prefix" : "apisix",
                        "token" : "apisix"
                    },
                    "key": "/apisix/secrets/vault/test1"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/secrets/vault/test1'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
        }
    }
--- response_body
passed



=== TEST 2: GET
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_GET,
                nil,
                [[{
                    "value": {
                        "uri": "http://127.0.0.1:12800/get",
                        "prefix" : "apisix",
                        "token" : "apisix"
                    },
                    "key": "/apisix/secrets/vault/test1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: GET all
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets',
                ngx.HTTP_GET,
                nil,
                [[{
                    "total": 1,
                    "list": [
                        {
                            "key": "/apisix/secrets/vault/test1",
                            "value": {
                                "uri": "http://127.0.0.1:12800/get",
                                "prefix" : "apisix",
                                "token" : "apisix"
                            }
                        }
                    ]
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: PATCH on path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/secrets/vault/test1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/secrets/vault/test1/token',
                ngx.HTTP_PATCH,
                [["unknown"]],
                [[{
                    "value": {
                        "uri": "http://127.0.0.1:12800/get",
                        "prefix" : "apisix",
                        "token" : "unknown"
                    },
                    "key": "/apisix/secrets/vault/test1"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/secrets/vault/test1'))
            assert(res.body.node.value.token == "unknown")
        }
    }
--- response_body
passed



=== TEST 5: PATCH
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/secrets/vault/test1'))
            local prev_create_time = res.body.node.value.create_time
            assert(prev_create_time ~= nil, "create_time is nil")
            local prev_update_time = res.body.node.value.update_time
            assert(prev_update_time ~= nil, "update_time is nil")
            ngx.sleep(1)

            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PATCH,
                [[{
                    "uri": "http://127.0.0.1:12800/get",
                    "prefix" : "apisix",
                    "token" : "apisix"
                }]],
                [[{
                    "value": {
                        "uri": "http://127.0.0.1:12800/get",
                        "prefix" : "apisix",
                        "token" : "apisix"
                    },
                    "key": "/apisix/secrets/vault/test1"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/secrets/vault/test1'))
            assert(res.body.node.value.token == "apisix")
        }
    }
--- response_body
passed



=== TEST 6: PATCH without id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault',
                ngx.HTTP_PATCH,
                [[{}]],
                [[{}]]
                )
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"no secret id"}



=== TEST 7: DELETE
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault/test1',
                 ngx.HTTP_DELETE
            )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: PUT with invalid format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/get",
                    "prefix" : "apisix",
                    "token" : "apisix"
                }]],
                [[{
                    "value": {
                        "uri": "http://127.0.0.1:12800/get",
                        "prefix" : "apisix",
                        "token" : "apisix"
                    },
                    "key": "/apisix/secrets/vault/test1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/validation failed: failed to match pattern/
