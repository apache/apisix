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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: set route with serverless-post-function plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "functions" : ["return function() if ngx.var.http_x_test_status ~= nil then;ngx.exit(tonumber(ngx.var.http_x_test_status));end;end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
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



=== TEST 2: test apisix with internal error code 500
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_body_like
.*apisix.apache.org.*



=== TEST 3: test apisix with internal error code 502
--- request
GET /hello
--- more_headers
X-Test-Status: 502
--- error_code: 502
--- response_body eval
qr/502 Bad Gateway/



=== TEST 4: test apisix with internal error code 503
--- request
GET /hello
--- more_headers
X-Test-Status: 503
--- error_code: 503
--- response_body eval
qr/503 Service Temporarily Unavailable/



=== TEST 5: test apisix with internal error code 504
--- request
GET /hello
--- more_headers
X-Test-Status: 504
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/



=== TEST 6: test apisix with upstream error code 500
--- request
GET /specific_status
--- more_headers
X-Test-Upstream-Status: 500
--- error_code: 500
--- response_body
upstream status: 500



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



=== TEST 8: set route which upstream is blocking
--- config
    location /t {
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
                    "uri": "/mysleep"
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



=== TEST 9: client abort
--- request
GET /mysleep?seconds=3
--- abort
--- timeout: 0.5
--- ignore_response
--- grep_error_log eval
qr/(stash|fetch) ngx ctx/
--- grep_error_log_out
stash ngx ctx
fetch ngx ctx
