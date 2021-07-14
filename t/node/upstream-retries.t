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

=== TEST 1: set upstream(id: 1), by default retries count = number of nodes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1": 1,
                        "127.0.0.2:1": 1,
                        "127.0.0.3:1": 1,
                        "127.0.0.4:1": 1
                    },
                    "type": "roundrobin"
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



=== TEST 2: set route(id: 1)
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



=== TEST 3: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 4: hit routes
--- request
GET /hello
--- error_code: 502
--- grep_error_log eval
qr/\[error\]/
--- grep_error_log_out
[error]
[error]
[error]
[error]



=== TEST 5: hit routes
--- request
GET /hello
--- error_code: 502
--- error_log
connect() failed



=== TEST 6: set upstream(id: 1), retries = 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1": 1,
                        "127.0.0.2:1": 1,
                        "127.0.0.3:1": 1,
                        "127.0.0.4:1": 1
                    },
                    "retries": 1,
                    "type": "roundrobin"
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



=== TEST 7: hit routes
--- request
GET /hello
--- error_code: 502
--- grep_error_log eval
qr/\[error\]/
--- grep_error_log_out
[error]
[error]



=== TEST 8: set upstream(id: 1), retries = 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1": 1,
                        "127.0.0.2:1": 1,
                        "127.0.0.3:1": 1,
                        "127.0.0.4:1": 1
                    },
                    "retries": 0,
                    "type": "roundrobin"
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



=== TEST 9: hit routes
--- request
GET /hello
--- error_code: 502
--- grep_error_log eval
qr/\[error\]/
--- grep_error_log_out
[error]



=== TEST 10: set upstream, retries > number of nodes, only try number of nodes time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1": 1,
                        "127.0.0.2:1": 1
                    },
                    "retries": 3,
                    "type": "roundrobin"
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



=== TEST 11: hit routes
--- request
GET /hello
--- error_code: 502
--- error_log
all upstream servers tried
--- grep_error_log eval
qr/connect\(\) failed/
--- grep_error_log_out
connect() failed
connect() failed



=== TEST 12: don't retry the same node twice
--- request
GET /hello
--- error_code: 502
--- error_log_like eval
qr/proxy request to 127.0.0.1:1
proxy request to 127.0.0.2:1
|proxy request to 127.0.0.2:1
proxy request to 127.0.0.1:1/



=== TEST 13: stop proxy to next upstream by retry_timeout
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 100,
                                "127.0.0.1:1981": 100,
                                "127.0.0.1:1982": 100
                            },
                            "retries": 10,
                            "retry_timeout": 2,
                            "type": "roundrobin"
                        },
                        "uri": "/mysleep"
                }]]
                )

            if code ~= 200 then
                ngx.say(body)
                return
            end
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/mysleep?abort=true&seconds=1"
            local res, err = httpc:request_uri(uri)
            if not res then
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
qr/proxy retry timeout, retry count: 2/
