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

=== TEST 1: set upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": [{
                        "host": "127.0.0.1",
                        "port": 8080,
                        "weight": 1
                    }],
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": [{
                                 "host": "127.0.0.1",
                                 "port": 8080,
                                 "weight": 1
                            }],
                            "type": "roundrobin",
                            "desc": "new upstream"
                        },
                        "key": "/apisix/upstreams/1"
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



=== TEST 2: get upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "node": {
                        "value": {
                            "nodes": [{
                                 "host": "127.0.0.1",
                                 "port": 8080,
                                 "weight": 1
                            }],
                            "type": "roundrobin",
                            "desc": "new upstream"
                        },
                        "key": "/apisix/upstreams/1"
                    },
                    "action": "get"
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



=== TEST 3: delete upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: delete upstream(id: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/upstreams/not_found',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )

            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404
--- no_error_log
[error]



=== TEST 5: push upstream + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/upstreams',
                 ngx.HTTP_POST,
                 [[{
                    "nodes": [{
                         "host": "127.0.0.1",
                         "port": 8080,
                         "weight": 1
                    }],
                    "type": "roundrobin"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": [{
                                "host": "127.0.0.1",
                                "port": 8080,
                                "weight": 1
                            }],
                            "type": "roundrobin"
                        }
                    },
                    "action": "create"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/upstreams/" + 1)
            code, message = t('/apisix/admin/upstreams/' .. id,
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 6: empty nodes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": [],
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(message)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: refer to empty nodes upstream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream_id": "1",
                    "uri": "/index.html"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(message)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: hit empty nodes upstream
--- request
GET /index.html
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 9: no additional properties is valid
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": [{
                          "host": "127.0.0.1",
                          "port": 8080,
                          "weight": 1
                    }],
                    "type": "roundrobin",
                    "invalid_property": "/index.html"
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
{"error_msg":"invalid configuration: additional properties forbidden, found invalid_property"}
--- no_error_log
[error]



=== TEST 10: invalid weight of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": [{
                          "host": "127.0.0.1",
                          "port": 8080,
                          "weight": "1"
                    }],
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 11: invalid weight of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": [{
                          "host": "127.0.0.1",
                          "port": 8080,
                          "weight": -100
                    }],
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 12: invalid port of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": [{
                          "host": "127.0.0.1",
                          "port": 0,
                          "weight": 1
                    }],
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 13: invalid host of node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams',
                 ngx.HTTP_PUT,
                 [[{
                    "id": 1,
                    "nodes": [{
                          "host": "127.#.%.1",
                          "port": 8080,
                          "weight": 1
                    }],
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
{"error_msg":"invalid configuration: property \"nodes\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]
