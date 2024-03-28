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

no_root_location();

run_tests();

__DATA__

=== TEST 1: set upstream with a invalid node port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "nodes": [{
                        "port": 65536,
                        "host": "127.0.0.1",
                        "weight": 1
                    }],
                    "type": "roundrobin"
                }]]
                )

            ngx.status = code

            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like
{"error_msg":"invalid configuration: property \\\"nodes\\\" validation failed: object matches none of the required"}



=== TEST 2: set upstream with a node port greater than 65535
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "nodes": {
                        "127.0.0.1:65536": 1
                     }
                }]]
                )

            ngx.status = code

            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like
{"error_msg":"invalid port 65536"}



=== TEST 3: set upstream with a node port less than 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "nodes": {
                     "127.0.0.1:0": 1
                     }
                }]]
                )

            ngx.status = code

            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like
{"error_msg":"invalid port 0"}
