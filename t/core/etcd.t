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
log_level("info");

run_tests;

__DATA__

=== TEST 1: delete test data if exists
--- config
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /delete
--- no_error_log
[error]
--- ignore_response



=== TEST 2: (add + update + delete) *2 (same uri)
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello",
"GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 200, 200, 200, 404, 201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n",
"passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- no_error_log
[error]
--- timeout: 5



=== TEST 3: add + update + delete + add + update + delete (different uris)
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/status"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /add2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello_"
                }]],
                nil
                )
                ngx.sleep(1)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello1"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /status", "GET /delete", "GET /status",
"GET /add2", "GET /hello_", "GET /update2", "GET /hello_", "GET /hello1", "GET /delete", "GET /hello1"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 200, 404, 200, 200, 404, 201, 200, 200, 404, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n", "ok\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n",
"passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n", "hello1 world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- no_error_log
[error]
--- timeout: 5



=== TEST 4: add*50 + update*50 + delete*50
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 25 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /add2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 26, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 25 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                    )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 26, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                    )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path, ngx.HTTP_DELETE)
            end
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /print_uri_20", "GET /add2", "GET /print_uri_36", "GET /update", "GET /print_uri_12", "GET /delete", "GET /print_uri_12"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "/print_uri_20\n", "passed\n", "/print_uri_36\n", "passed\n", "/print_uri_12\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- no_error_log
[error]
--- timeout: 20



=== TEST 5: get single
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/ab", "ab"))
            local res, err = etcd.get("/a")
            ngx.status = res.status
        }
    }
--- request
GET /t
--- error_code: 404
--- no_error_log
[error]



=== TEST 6: get prefix
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/ab", "ab"))
            local res, err = etcd.get("/a", true)
            ngx.status = res.status
            ngx.say(res.body.node.value)
        }
    }
--- request
GET /t
--- response_body
ab
--- no_error_log
[error]
