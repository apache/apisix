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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set upstream(id: 1) invalid parameters
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "type": "roundrobin",
                    "desc": "new upstream"
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
--- no_error_log
[error]



=== TEST 2: set upstream(id: 1) nodes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
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



=== TEST 3: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream_id": "1"
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



=== TEST 4: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 5: hit routes
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: delete upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
            )
            ngx.print("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 400 message: {"error_msg":"can not delete this upstream, route [1] is still using it now"}
--- no_error_log
[error]



=== TEST 7: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
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



=== TEST 8: delete upstream(id: 1)
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



=== TEST 9: delete upstream again(id: 1)
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
            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404
--- no_error_log
[error]



=== TEST 10: set upstream(id: 1, using `node` mode to pass upstream host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "httpbin.org:80": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream",
                    "pass_host": "node"
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



=== TEST 11: set route(id: 1, using `node` mode to pass upstream host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/get",
                    "upstream_id": "1"
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



=== TEST 12: hit route
--- request
GET /get
--- response_body eval
qr/"Host": "httpbin.org"/
--- no_error_log
[error]



=== TEST 13: set upstream(using `rewrite` mode to pass upstream host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream",
                    "pass_host": "rewrite",
                    "upstream_host": "httpbin.org"
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



=== TEST 14: set route(using `rewrite` mode to pass upstream host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/uri",
                    "upstream_id": "1"
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



=== TEST 15: hit route
--- request
GET /uri
--- response_body eval
qr/host: httpbin.org/
--- no_error_log
[error]



=== TEST 16: delete upstream in used
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            ngx.sleep(0.5) -- wait for data synced
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"can not delete this upstream, route [1] is still using it now"}
--- no_error_log
[error]



=== TEST 17: multi nodes with `node` mode to pass host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "localhost:1979": 1000,
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin",
                    "pass_host": "node"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/uri",
                    "upstream_id": "1"
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
--- skip_nginx: 5: < 1.19.0
--- response_body
passed
--- no_error_log
[error]



=== TEST 18: hit route
--- request
GET /uri
--- skip_nginx: 5: < 1.19.0
--- response_body eval
qr/host: 127.0.0.1/
--- error_log
proxy request to 127.0.0.1:1980



=== TEST 19: multi nodes with `node` mode to pass host, the second node has domain
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:1979": 1000,
                        "localhost:1980": 1
                    },
                    "type": "roundrobin",
                    "pass_host": "node"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/uri",
                    "upstream_id": "1"
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
--- skip_nginx: 5: < 1.19.0
--- response_body
passed
--- no_error_log
[error]



=== TEST 20: hit route
--- request
GET /uri
--- skip_nginx: 5: < 1.19.0
--- response_body eval
qr/host: localhost/
--- error_log
proxy request to 127.0.0.1:1980
