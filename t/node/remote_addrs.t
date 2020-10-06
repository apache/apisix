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
                    "uri": "/hello",
                    "remote_addrs": ["192.0.0.0/8", "127.0.0.3"],
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



=== TEST 2: /not_found
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 3: /not_found
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
Host: not_found.com
--- error_code: 404
--- no_error_log
[error]



=== TEST 4: hit routes
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
X-Real-IP: 192.168.1.100
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: hit routes
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
X-Real-IP: 127.0.0.3
--- response_body
hello world
--- no_error_log
[error]
