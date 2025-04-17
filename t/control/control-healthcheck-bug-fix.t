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

=== TEST 1: setup route
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
                            "httpbin.org:80": 1,
                            "mockbin.org:80": 1
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



=== TEST 2: hit the route
--- request
GET /status/403
--- error_code: 403



=== TEST 3: hit control api
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local passed = true

            for i = 1, 40 do
                local code, body, res = t.test('/v1/routes/1', ngx.HTTP_GET)
                if code ~= ngx.HTTP_OK then
                    passed = code
                    break
                end
            end

            if passed then
                ngx.say("passed")
            else
                ngx.say("failed. got status code: ", passed)
            end
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: hit the route again
--- request
GET /status/403
--- error_code: 403



=== TEST 5: hit control api
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local passed = true

            for i = 1, 40 do
                local code, body, res = t.test('/v1/routes/1', ngx.HTTP_GET)
                if code ~= ngx.HTTP_OK then
                    passed = code
                    break
                end
            end

            if passed then
                ngx.say("passed")
            else
                ngx.say("failed. got status code: ", passed)
            end
        }
    }
--- request
GET /t
--- response_body
passed
