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

=== TEST 1: sanity check
--- config
location /t {
    content_by_lua_block {
        -- let the server info to be reported
        ngx.sleep(5.1)
        local json_decode = require("cjson.safe").decode
        local t = require("lib.test_admin").test
        local code, _, body = t('/apisix/admin/server_info', ngx.HTTP_GET, nil, nil)
        if code >= 300 then
            ngx.status = code
        end

        local keys = {}
        body = json_decode(body)
        for k in pairs(body) do
            keys[#keys + 1] = k
        end

        table.sort(keys)
        for i = 1, #keys do
            ngx.say(keys[i], ": ", body[keys[i]])
        end
    }
}
--- request
GET /t
--- response_body eval
qr{^etcd_version: [\d\.]+
hostname: \w+
id: [a-zA-Z\-0-9]+
last_report_time: \d+
up_time: \d+
version: [\d\.]+
$}
--- timeout: 6
--- no_error_log
[error]



=== TEST 2: uninitialized server info
--- config
location /t {
    content_by_lua_block {
        local json_decode = require("cjson.safe").decode
        local t = require("lib.test_admin").test
        local code, _, body = t('/apisix/admin/server_info', ngx.HTTP_GET, nil, nil)
        if code >= 300 then
            ngx.status = code
        end

        local keys = {}
        body = json_decode(body)
        for k in pairs(body) do
            keys[#keys + 1] = k
        end

        table.sort(keys)
        for i = 1, #keys do
            ngx.say(keys[i], ": ", body[keys[i]])
        end
    }
}
--- request
GET /t
--- response_body eval
qr{^etcd_version: unknown
hostname: \w+
id: [a-zA-Z\-0-9]+
last_report_time: -1
up_time: \d+
version: [\d\.]+
$}
--- no_error_log
[error]
