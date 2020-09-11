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

=== TEST 1: delete if needed
--- config
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /delete
--- ignore_response

=== TEST 2: add + update + delete
--- config
    location /add {
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
                    "methods": ["GET"],
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
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"failed to match any routes\"}\n"]
--- no_error_log
[error]

=== TEST 3: add*10 + update*10 + delete*10
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local uri = ""
            local host = ""
            local code, body
            for i = 1, 10 do
                uri = '/apisix/admin/routes/' .. tostring(i)
                host = "foo-" .. tostring(i)
                code, body = t(uri,
                    ngx.HTTP_PUT,
                    string.format('{"methods": ["GET"],"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "%s","uri": "/hello"}', host),
                    nil
                    )
            end
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local uri = ""
            local host = ""
            local code, body
            for i = 1, 10 do
                uri = '/apisix/admin/routes/' .. tostring(i)
                host = "foo-" .. tostring(i)
                code, body = t(uri,
                    ngx.HTTP_PUT,
                    string.format('{"methods": ["GET"],"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "%s","uri": "/hello"}', host),
                    nil
                    )
            end
            
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body
            for i = 1, 10 do
                uri = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(uri,
                    ngx.HTTP_DELETE,
                    nil,
                    [[{
                        "action": "delete"
                    }]]
                    )
            end
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello"]
--- more_headers
Host: foo-7
--- error_code eval
[201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"failed to match any routes\"}\n"]
--- no_error_log
[error]
