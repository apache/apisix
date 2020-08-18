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

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "host": "*.foo.com",
                        "uri": "/hello"
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



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]



=== TEST 3: /not_found
--- request
GET /hello
--- error_code: 404
--- no_error_log
[error]



=== TEST 4: /not_found
--- request
GET /hello
--- more_headers
Host: not_found.com
--- error_code: 404
--- no_error_log
[error]



=== TEST 5: hit routes (www.foo.com)
--- request
GET /hello
--- more_headers
Host: www.foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: hit routes (user.foo.com)
--- request
GET /hello
--- more_headers
Host: user.foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 7: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "host": "foo.com",
                        "uri": "/hello"
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



=== TEST 8: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]



=== TEST 9: /not_found
--- request
GET /hello
--- error_code: 404
--- no_error_log
[error]



=== TEST 10: /not_found
--- request
GET /hello
--- more_headers
Host: www.foo.com
--- error_code: 404
--- no_error_log
[error]



=== TEST 11: hit routes (foo.com)
--- request
GET /hello
--- more_headers
Host: foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 12: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "filter_func": "function(vars) return vars.arg_name == 'json' end",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 13: not hit: name=unknown
--- request
GET /hello?name=unknown
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]



=== TEST 14: hit routes
--- request
GET /hello?name=json
--- response_body
hello world
--- no_error_log
[error]
