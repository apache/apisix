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
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 42: set route with ttl
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local core = require("apisix.core")
        -- set
        local code, body, res = t('/apisix/admin/routes/1?ttl=1',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/index.html"
            }]]
            )

        ngx.say("code: ", code)
        ngx.say(body)

        -- get
        code, body = t('/apisix/admin/routes/1?ttl=1',
            ngx.HTTP_GET,
            nil,
            [[{
                "value": {
                    "uri": "/index.html"
                },
                "key": "/apisix/routes/1"
            }]]
        )

        ngx.say("code: ", code)
        ngx.say(body)

        ngx.sleep(2)

        -- get again
        code, body, res = t('/apisix/admin/routes/1', ngx.HTTP_GET)

        ngx.say("code: ", code)
        ngx.say("message: ", core.json.decode(body).message)
    }
}
--- request
GET /t
--- response_body
code: 200
passed
code: 200
passed
code: 404
message: Key not found
--- no_error_log
[error]
--- timeout: 5