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

run_tests;

__DATA__

=== TEST 1: create consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
            )

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: set service and enabled plugin `key-auth`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
                    },
                    "desc": "new service"
                }]]
            )
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: create route with plugin `limit-req`(upstream node contains domain)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 1,
                            "burst": 0,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "www.apiseven.com:80": 1
                        },
                        "pass_host": "node",
                        "type": "roundrobin"
                    },
                    "service_id": 1,
                    "uri": "/index.html"
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



=== TEST 4: hit route 3 times
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local headers = {
            ["User-Agent"] = "curl/7.68.0",
            ["apikey"] = "auth-one",
        }

        for i = 1, 3 do
            local code, body = t.test('/index.html',
                ngx.HTTP_GET,
                "",
                nil,
                headers
            )
            ngx.say("return: ", code)
        end
    }
}
--- request
GET /t
--- response_body
return: 302
return: 503
return: 503
--- no_error_log
[error]
--- timeout: 5



=== TEST 5: set upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "www.apiseven.com:80": 1
                    },
                    "pass_host": "node",
                    "type": "roundrobin"
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



=== TEST 6: create route with plugin `limit-req`, and bind upstream via id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 1,
                            "burst": 0,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream_id": 1,
                    "service_id": 1,
                    "uri": "/index.html"
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



=== TEST 7: hit route 3 times
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local headers = {
            ["User-Agent"] = "curl/7.68.0",
            ["apikey"] = "auth-one",
        }

        for i = 1, 3 do
            local code, body = t.test('/index.html',
                ngx.HTTP_GET,
                "",
                nil,
                headers
            )
            ngx.say("return: ", code)
        end
    }
}
--- request
GET /t
--- response_body
return: 302
return: 503
return: 503
--- no_error_log
[error]
--- timeout: 5
