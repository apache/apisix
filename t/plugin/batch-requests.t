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
log_level("debug");

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "query": {
                        "base": "base_query",
                        "conflict": "query_value"
                    },
                    "headers": {
                        "Base-Header": "base",
                        "ConflictHeader": "header_value",
                        "OuterConflict": "common_value"
                    },
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world",
                            "ConflictHeader": "b-header-value"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d",
                        "query": {
                            "one": "thing",
                            "conflict": "d_value"
                        }
                    }]
                }]=],
                [=[[
                {
                    "status": 200,
                    "body":"B",
                    "headers": {
                        "Base-Header": "base",
                        "Base-Query": "base_query",
                        "X-Res": "B",
                        "X-Header1": "hello",
                        "X-Header2": "world",
                        "X-Conflict-Header": "b-header-value",
                        "X-OuterConflict": "common_value"
                    }
                },
                {
                    "status": 201,
                    "body":"C",
                    "headers": {
                        "Base-Header": "base",
                        "Base-Query": "base_query",
                        "X-Res": "C",
                        "X-Method": "PUT"
                    }
                },
                {
                    "status": 202,
                    "body":"D",
                    "headers": {
                        "Base-Header": "base",
                        "Base-Query": "base_query",
                        "X-Res": "D",
                        "X-Query-One": "thing",
                        "X-Query-Conflict": "d_value"
                    }
                }
                ]]=],
                {
                    ConflictHeader = "outer_header",
                    OuterConflict = "outer_conflict"
                })

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.status = 200
            ngx.header["Base-Header"] = ngx.req.get_headers()["Base-Header"]
            ngx.header["Base-Query"] = ngx.var.arg_base
            ngx.header["X-Header1"] = ngx.req.get_headers()["Header1"]
            ngx.header["X-Header2"] = ngx.req.get_headers()["Header2"]
            ngx.header["X-Conflict-Header"] = ngx.req.get_headers()["ConflictHeader"]
            ngx.header["X-OuterConflict"] = ngx.req.get_headers()["OuterConflict"]
            ngx.header["X-Res"] = "B"
            ngx.print("B")
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["Base-Header"] = ngx.req.get_headers()["Base-Header"]
            ngx.header["Base-Query"] = ngx.var.arg_base
            ngx.header["X-Res"] = "C"
            ngx.header["X-Method"] = ngx.req.get_method()
            ngx.print("C")
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.status = 202
            ngx.header["Base-Header"] = ngx.req.get_headers()["Base-Header"]
            ngx.header["Base-Query"] = ngx.var.arg_base
            ngx.header["X-Query-One"] = ngx.var.arg_one
            ngx.header["X-Query-Conflict"] = ngx.var.arg_conflict
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



=== TEST 2: missing pipeline
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
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
{"error_msg":"bad request body: object matches none of the requireds: [\"pipeline\"]"}
--- no_error_log
[error]



=== TEST 3: timeout is not number
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
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
{"error_msg":"bad request body: property \"timeout\" validation failed: wrong type: expected integer, got string"}
--- no_error_log
[error]



=== TEST 4: different response time
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
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
            local code, body = t('/apisix/batch-requests',
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
                    "status": 504,
                    "reason": "upstream timeout"
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
            local code, body = t('/apisix/batch-requests',
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
                    "status": 504,
                    "reason": "upstream timeout"
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



=== TEST 7: no body in request
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                nil,
                nil
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /aggregate
--- error_code: 400
--- response_body
{"error_msg":"no request body, you should give at least one pipeline setting"}
--- no_error_log
[error]



=== TEST 8: invalid body
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                "invalid json string"
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /aggregate
--- error_code: 400
--- response_body
{"error_msg":"invalid request body: invalid json string, err: Expected value but found invalid token at character 1"}
--- no_error_log
[error]



=== TEST 9: invalid pipeline's path
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "pipeline":[
                    {
                        "path": ""
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
{"error_msg":"bad request body: property \"pipeline\" validation failed: failed to validate item 1: property \"path\" validation failed: string too short, expected at least 1, got 0"}
--- no_error_log
[error]



=== TEST 10: invalid pipeline's method
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "pipeline":[{
                        "path": "/c",
                        "method": "put"
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
{"error_msg":"bad request body: property \"pipeline\" validation failed: failed to validate item 1: property \"method\" validation failed: matches none of the enum values"}
--- no_error_log
[error]



=== TEST 11: invalid pipeline's version
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "pipeline":[{
                        "path": "/d",
                        "version":1.2
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
{"error_msg":"bad request body: property \"pipeline\" validation failed: failed to validate item 1: property \"version\" validation failed: matches none of the enum values"}
--- no_error_log
[error]



=== TEST 12: invalid pipeline's ssl
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "pipeline":[{
                        "path": "/d",
                        "ssl_verify":1.2
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
{"error_msg":"bad request body: property \"pipeline\" validation failed: failed to validate item 1: property \"ssl_verify\" validation failed: wrong type: expected boolean, got number"}
--- no_error_log
[error]



=== TEST 13: invalid pipeline's number
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "pipeline":[]
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
{"error_msg":"bad request body: property \"pipeline\" validation failed: expect array to have at least 1 items"}
--- no_error_log
[error]



=== TEST 14: when client body has been wrote to temp file
--- config
    client_body_in_file_only on;
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
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
--- no_error_log
[error]



=== TEST 15: copy all header to every request except content
--- config
    client_body_in_file_only on;
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 1000,
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
                        "headers": {
                            "X-Cookie": "request-cookies-b",
                            "X-HeaderB": "request-header-b"
                        }
                    },
                    {
                        "status": 201,
                        "headers": {
                            "X-Cookie": "request-cookies-c",
                            "X-HeaderC": "request-header-c"
                        }
                    },
                    {
                        "status": 202,
                        "headers": {
                            "X-Cookie": "request-cookies-d",
                            "X-HeaderD": "request-header-d"
                        }
                    }
                ]]=],
                {
                    Cookie = "request-cookies",
                    OuterHeader = "request-header"
                })

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.status = 200
            ngx.header["X-Cookie"] = ngx.req.get_headers()["Cookie"] .. "-b"
            ngx.header["X-HeaderB"] = ngx.req.get_headers()["OuterHeader"] .. "-b"
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["X-Cookie"] = ngx.req.get_headers()["Cookie"] .. "-c"
            ngx.header["X-HeaderC"] = ngx.req.get_headers()["OuterHeader"] .. "-c"
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.status = 202
            ngx.header["X-Cookie"] = ngx.req.get_headers()["Cookie"] .. "-d"
            ngx.header["X-HeaderD"] = ngx.req.get_headers()["OuterHeader"] .. "-d"
        }
    }
--- request
GET /aggregate
--- response_body
passed
--- no_error_log
[error]



=== TEST 16: exceed default body limit size (check header)
--- config
    location = /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 ("1234"):rep(1024 * 1024)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 413
--- response_body eval
qr/\{"error_msg":"request size 4194304 is greater than the maximum size 1048576 allowed"\}/
--- no_error_log
[error]



=== TEST 17: exceed default body limit size (check file size)
--- request eval
"POST /apisix/batch-requests
" . ("1000\r
" . ("11111111" x 512) . "\r
") x 257 . "0\r
\r
"
--- more_headers
Transfer-Encoding: chunked
--- error_code: 413
--- response_body eval
qr/\{"error_msg":"request size 1052672 is greater than the maximum size 1048576 allowed"\}/
--- no_error_log
[error]
--- error_log
attempt to read body from file



=== TEST 18: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/batch-requests',
                ngx.HTTP_PUT,
                [[{
                    "max_body_size": 2048
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



=== TEST 19: exceed body limit size
--- config
    location = /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 ("1234"):rep(1024)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 413
--- response_body eval
qr/\{"error_msg":"request size 4096 is greater than the maximum size 2048 allowed"\}/
--- no_error_log
[error]



=== TEST 20: exceed body limit size (expected)
--- config
    location = /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, res_data = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 ("1234"):rep(1024),
                 nil,
                 {EXPECT = "100-CONTINUE", ["content-length"] = 4096}
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 413
--- response_body eval
qr/\{"error_msg":"request size 4096 is greater than the maximum size 2048 allowed"\}/
--- no_error_log
[error]



=== TEST 21: don't exceed body limit size
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "headers": {
                        "Base-Header": "base"
                    },
                    "pipeline":[
                    {
                        "path": "/a",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    }
                    ]
                }]=],
                [=[[
                {
                    "status": 200,
                    "body":"A",
                    "headers": {
                        "Base-Header": "base",
                        "X-Res": "a",
                        "X-Header1": "hello",
                        "X-Header2": "world"
                    }
                }
                ]]=])

            ngx.status = code
            ngx.say(body)
        }
    }
    location = /a {
        content_by_lua_block {
            ngx.status = 200
            ngx.header["Base-Header"] = ngx.req.get_headers()["Base-Header"]
            ngx.header["X-Header1"] = ngx.req.get_headers()["Header1"]
            ngx.header["X-Header2"] = ngx.req.get_headers()["Header2"]
            ngx.header["X-Res"] = "a"
            ngx.print("A")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 22: invalid body size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/batch-requests',
                ngx.HTTP_PUT,
                [[{
                    "max_body_size": 0
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
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid configuration: property \\"max_body_size\\" validation failed: expected 0 to be strictly greater than 0"\}/
--- no_error_log
[error]



=== TEST 23: keep environment clean
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/batch-requests',
                ngx.HTTP_PUT,
                [[{
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
