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

worker_connections(256);
no_root_location();

run_tests();

__DATA__

=== TEST 1: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
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



=== TEST 2: set route (different upstream)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 3: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]



=== TEST 4: hit routes
--- request
GET /server_port
--- response_headers
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
--- response_body eval
qr/1981/
--- no_error_log
[error]



=== TEST 5: set route with empty plugins, should do nothing
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {},
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 6: hit routes
--- request
GET /server_port
--- response_headers
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
--- response_body eval
qr/1980/
--- no_error_log
[error]



=== TEST 7: disable plugin `limit-count`
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "disable": true
                        }
                    },
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 8: hit routes
--- request
GET /server_port
--- raw_response_headers_unlike eval
qr/X-RateLimit-Limit/
--- response_body eval
qr/1980/
--- no_error_log
[error]



=== TEST 9: hit routes two times, checker service configuration
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.2)
        local t = require("lib.test_admin").test
        local code, body = t('/server_port',
            ngx.HTTP_GET
        )
        ngx.say(body)

        code, body = t('/server_port',
            ngx.HTTP_GET
        )
        ngx.say(body)
    }
}
--- request
GET /t
--- error_log eval
[qr/merge_service_route.*"time_window":60,/,
qr/merge_service_route.*"time_window":60,/]
