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

repeat_each(3);
#no_long_string();
no_root_location();
log_level('info');
run_tests;

__DATA__

=== TEST 1: add upstream
--- http_config
lua_shared_dict balancer_ewma 1m;
lua_shared_dict balancer_ewma_last_touched_at 1m;
lua_shared_dict balancer_ewma_locks 1m;
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "10.12.7.103:28002": 100,
                                "10.12.7.103:29002": 100
                            },
                            "type": "ewma"
                        },
                        "uri": "/delay"
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "10.12.7.103:28002": 100,
                                    "10.12.7.103:29002": 100
                                },
                                "type": "ewma"
                            },
                            "uri": "/delay"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 2: access
--- http_config
lua_shared_dict balancer_ewma 1m;
lua_shared_dict balancer_ewma_last_touched_at 1m;
lua_shared_dict balancer_ewma_locks 1m;
--- request
GET /delay
--- error_code: 200
--- no_error_log
[error]
