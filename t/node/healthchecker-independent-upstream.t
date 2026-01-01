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

=== TEST 1: using route with an upstream id reference should also trigger healthcheck_manager
--- extra_init_by_lua
    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
    
        count = count + 1
        if domain == "test1.com" then
            return {address = "127.0.0." .. count}
        end
        if domain == "test2.com" then
            return {address = "127.0.0." .. count+100}
        end

        error("unknown domain: " .. domain)
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "test1.com:1980": 1,
                        "test2.com:1980": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream",
                    "checks": {
                        "active": {
                            "http_path": "/status",
                            "healthy": {
                                "interval": 1,
                                "successes": 4
                            },
                            "unhealthy": {
                                "interval": 1,
                                "http_failures": 1
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            for _, _ in ipairs({1, 2, 3, 4, 5}) do
                code, body = t('/hello', ngx.HTTP_GET)
                if code >= 300 then
                    ngx.status = code
                    return
                end
                ngx.sleep(1)
            end
            ngx.say(body)
        }
    }
--- timeout: 10
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/create new checker: table: /
--- grep_error_log_out
create new checker: table: 
create new checker: table: 
create new checker: table: 
create new checker: table: 
create new checker: table: 
