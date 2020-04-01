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

=== TEST 1: sanity
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                 ngx.HTTP_POST,
                 [=[{
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=],
                [=[[
                {
                    "status": 200,
                    "body":"B",
                    "headers": {
                        "X-Res": "B",
                        "X-Header1": "hello",
                        "X-Header2": "world"
                    }
                },
                {
                    "status": 201,
                    "body":"C",
                    "headers": {
                        "X-Res": "C",
                        "X-Method": "PUT"
                    }
                },
                {
                    "status": 202,
                    "body":"D",
                    "headers": {
                        "X-Res": "D"
                    }
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.status = 200
            ngx.header["X-Header1"] = ngx.req.get_headers()["Header1"]
            ngx.header["X-Header2"] = ngx.req.get_headers()["Header2"]
            ngx.header["X-Res"] = "B"
            ngx.print("B")
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["X-Res"] = "C"
            ngx.header["X-Method"] = ngx.req.get_method()
            ngx.print("C")
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.status = 202
            ngx.header["X-Res"] = "D"
            ngx.print("D")
        }
    }
--- request
GET /aggregate
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: missing pipeling
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                ngx.HTTP_POST,
                [=[{
                    "pipeline1":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /aggregate
--- error_code: 400
--- response_body
{"message":"missing 'pipeline' in input"}
--- no_error_log
[error]



=== TEST 3: timeout is not number
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                ngx.HTTP_POST,
                [=[{
                    "timeout": "200",
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /aggregate
--- error_code: 400
--- response_body
{"message":"'timeout' should be number"}
--- no_error_log
[error]



=== TEST 4: different response time
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 2000,
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                },
                {
                    "status": 201
                },
                {
                    "status": 202
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.sleep(0.02)
            ngx.status = 200
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.sleep(0.05)
            ngx.status = 201
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.status = 202
        }
    }
--- request
GET /aggregate
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: last request timeout
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                },
                {
                    "status": 201
                },
                {
                    "status": 500,
                    "reason": "target timeout"
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.status = 200
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.status = 202
        }
    }
--- request
GET /aggregate
--- response_body
passed
--- error_log
timeout



=== TEST 6: first request timeout
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/aggregate',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=],
                [=[[
                {
                    "status": 500,
                    "reason": "target timeout"
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.status = 200
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.status = 202
        }
    }
--- request
GET /aggregate
--- response_body
passed
--- error_log
timeout
