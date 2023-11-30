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
                            "type": "roundrobin",
                            "timeout": {
                                "connect": 0.5,
                                "send": 0.5,
                                "read": 0.5
                            }
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



=== TEST 2: hit routes (timeout)
--- request
GET /mysleep?seconds=1
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/
--- error_log
timed out) while reading response header from upstream



=== TEST 3: set custom timeout for route(overwrite upstream timeout)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "timeout": {
                            "connect": 0.5,
                            "send": 0.5,
                            "read": 0.5
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin",
                            "timeout": {
                                "connect": 2,
                                "send": 2,
                                "read": 2
                            }
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



=== TEST 4: hit routes (timeout)
--- request
GET /mysleep?seconds=1
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/
--- error_log
timed out) while reading response header from upstream



=== TEST 5: set route inherit hosts from service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local scode, sbody = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                       "desc":"test-service",
                       "hosts": ["foo.com"]
                }]]
                )

            if scode >= 300 then
                ngx.status = scode
            end
            ngx.say(sbody)

            local rcode, rbody = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "service_id": "1",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin",
                            "timeout": {
                                "connect": 0.5,
                                "send": 0.5,
                                "read": 0.5
                            }
                        },
                        "uri": "/mysleep"
                }]]
                )

            if rcode >= 300 then
                ngx.status = rcode
            end
            ngx.say(rbody)
        }
    }
--- request
GET /t
--- response_body
passed
passed



=== TEST 6: hit service route (timeout)
--- request
GET /mysleep?seconds=1
--- more_headers
Host: foo.com
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/
--- error_log
timed out) while reading response header from upstream
