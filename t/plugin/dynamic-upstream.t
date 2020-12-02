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
log_level("info");

run_tests;

__DATA__

=== TEST 1: a `vars` rule and a plugin `upstream`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                ["arg_name", "==", "jack"],
                                                ["arg_age", "!","<", "16"]
                                            ]
                                        }
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {"name": "upstream_A", "type": "roundrobin", "nodes": {"127.0.0.1:1981":2}, "timeout": {"connect": 15, "send": 15, "read": 15}},
                                            "weight": 2
                                        },
                                        {
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
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



=== TEST 2: expression validation failed, return to the default `route` upstream port `1980`
--- request
GET /server_port?name=jack&age=14
--- response_body eval
1980
--- no_error_log
[error]



=== TEST 3: the expression passes and returns to the `1981` port
--- request
GET /server_port?name=jack&age=16
--- response_body eval
1981
--- no_error_log
[error]



=== TEST 4: the expression passes and initiated multiple requests
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        for i = 1, 6 do
            local _, _, body = t('/server_port?name=jack&age=16', ngx.HTTP_GET)
            bodys[i] = body
        end
        table.sort(bodys)
        ngx.say(table.concat(bodys, ", "))
    }
}
--- request
GET /t
--- response_body
1980, 1980, 1981, 1981, 1981, 1981
--- no_error_log
[error]



=== TEST 5: Multiple vars rules and multiple plugin upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/server_port",
                    "plugins": {
                        "dynamic-upstream": {
                            "rules": [
                                {
                                    "match": [
                                        {
                                            "vars": [
                                                ["arg_name", "==", "jack"],
                                                ["arg_age", "~~", "[1-9]*"]
                                            ]
                                        },
                                        {
                                            "vars": [
                                                ["arg_name2", "~*=", "[A-Z]*"],
                                                ["arg_age", "!", "<", 18]
                                            ]
                                        }
                                    ],
                                    "upstreams": [
                                        {
                                           "upstream": {
                                                "name": "upstream_A",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1981":20
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 2
                                        },
                                        {
                                           "upstream": {
                                                "name": "upstream_B",
                                                "type": "roundrobin",
                                                "nodes": {
                                                   "127.0.0.1:1982":10
                                                },
                                                "timeout": {
                                                    "connect": 15,
                                                    "send": 15,
                                                    "read": 15
                                                }
                                            },
                                            "weight": 1
                                        },
                                        {
                                            "weight": 1
                                        }
                                    ]
                                }
                            ]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    }
                }]=]
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
