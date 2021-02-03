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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity, batch_max_size=1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1980/log",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "concat_method": "new_line"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
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



=== TEST 2: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log eval
qr/request log: .*"upstream":"127.0.0.1:1982"/



=== TEST 3: sanity, batch_max_size=1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1980/log",
                                "batch_max_size": 3,
                                "max_retry_count": 3,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 1,
                                "concat_method": "new_line"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
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



=== TEST 4: hit route, and no report log
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
request log:



=== TEST 5: hit route, and report log
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 6 do
            t('/hello', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- timeout: 10
--- no_error_log
[error]
--- grep_error_log eval
qr/request log:/
--- grep_error_log_out
request log:
request log:



=== TEST 6: hit route, and report log
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 6 do
            t('/hello', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- timeout: 10
--- no_error_log
[error]
--- grep_error_log eval
qr/"upstream":"127.0.0.1:1982"/
--- grep_error_log_out
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"



=== TEST 7: hit route, and report log
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 5 do
            t('/hello', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- timeout: 10
--- no_error_log
[error]
--- grep_error_log eval
qr/"upstream":"127.0.0.1:1982"/
--- grep_error_log_out
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"
"upstream":"127.0.0.1:1982"



=== TEST 8: set in global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 3,
                            "max_retry_count": 3,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "inactive_timeout": 1,
                            "concat_method": "new_line"
                        }
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



=== TEST 9: not hit route, and report log
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 5 do
            t('/not_hit_route', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- timeout: 10
--- no_error_log
[error]



=== TEST 10: delete the global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE
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
