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

master_on();
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.5)
        local t = require("lib.test_admin").test
        local code, body, body_org = t('/apisix/status', ngx.HTTP_GET)

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body_org)
    }
}
--- request
GET /t
--- response_body eval
qr/"accepted":/
--- no_error_log
[error]



=== TEST 2: get node status
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local t = require("lib.test_admin").test
            local code, body, body_org = t('/apisix/admin/node_status',
                ngx.HTTP_GET
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body_org)
        }
    }
--- request
GET /t
--- response_body eval
qr/"accepted"/
--- no_error_log
[error]



=== TEST 3: test for unsupported method
--- request
PATCH /apisix/status
--- error_code: 404
