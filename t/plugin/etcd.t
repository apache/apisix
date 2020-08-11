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
no_shuffle();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.prometheus")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.prometheus")
            local ok, err = plugin.check_schema({
                invalid = "invalid"
                })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
additional properties forbidden, found invalid
--- no_error_log
[error]



=== TEST 3: set it in route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "prometheus": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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



=== TEST 4: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body_like
apisix_etcd_reachable 1
--- no_error_log
[error]

=== TEST 5: request from client (all hit)
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 6: request from client (part hit)
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 200, 404, 200, 200]
--- no_error_log
[error]



=== TEST 7: fetch the prometheus metric data
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_bandwidth\{type="egress",route="1",service="",node="127.0.0.1"\} \d+/
--- no_error_log
[error]

