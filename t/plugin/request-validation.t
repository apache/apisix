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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-validation")
            local ok, err = plugin.check_schema({body_schema = {}})
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



=== TEST 2: missing schema for header and body
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-validation")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body_like eval
qr/object matches none of the required/



=== TEST 3: add plugin with all combinations
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                plugins = {
                    ["request-validation"] = {
                    body_schema = {
                        type = "object",
                        required = { "required_payload" },
                        properties = {
                        required_payload = {
                            type = "string"
                        },
                        boolean_payload = {
                            type = "boolean"
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        },
                        req_headers = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string"
                            }
                        }
                        }
                    }
                    }
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1982"] = 1
                    },
                    type = "roundrobin"
                },
                uri = "/opentracing"
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
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



=== TEST 4: required payload missing
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = '{"boolean-payload": true}',
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.status == 400 then
                ngx.say("required field missing")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
required field missing
--- error_log
property "required_payload" is required



=== TEST 5: required payload added
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = '{"boolean-payload": true,' ..
                    '"required_payload": "hello"}',
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.status == 200 then
                ngx.say("hello1 world")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
hello1 world
--- no_error_log



=== TEST 6: Add plugin with header_schema
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                plugins = {
                    ["request-validation"] = {
                    header_schema = {
                        type = "object",
                        required = { "required_payload" },
                        properties = {
                        required_payload = {
                            type = "string"
                        },
                        boolean_payload = {
                            type = "boolean"
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        },
                        req_headers = {
                            type = "array",
                            minItems = 1,
                            items = {
                            type = "string"
                            }
                        }
                        }
                    }
                    }
                },
                upstream = {
                    nodes = {
                    ["127.0.0.1:1982"] = 1
                    },
                    type = "roundrobin"
                },
                uri = "/opentracing"
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
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



=== TEST 7: required header payload missing
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

            if res.status == 400 then
                ngx.say("required field missing")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
required field missing
--- error_log
property "required_payload" is required



=== TEST 8: required header added in header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["required_payload"] = "test payload"
                    }
                })

            if res.status == 200 then
                ngx.say("hello1 world")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
hello1 world



=== TEST 9: add route (test request validation `body_schema`)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "required": ["required_payload"],
                                "properties": {
                                    "required_payload": {"type": "string"},
                                    "boolean_payload": {"type": "boolean"},
                                    "timeouts": {
                                       "type": "integer",
                                        "minimum": 1,
                                        "maximum": 254,
                                        "default": 3
                                    },
                                    "req_headers": {
                                        "type": "array",
                                        "minItems": 1,
                                        "items": {
                                            "type": "string"
                                        }
                                    }
                                }
                            }
                        }
                    },]] .. [[
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 10: add route (test request validation `body_schema.type` is object)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 11: add route (test request validation `body_schema.type` is array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "array"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 12: add route (test request validation `body_schema.type` is string)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "string"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 13: add route (test request validation `body_schema.type` is number)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "number"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 14: add route (test request validation `body_schema.type` is integer)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "integer"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 15: add route (test request validation `body_schema.type` is table)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "table"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 16: add route (test request validation `body_schema.type` is function)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "function"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 17: add route (test request validation `body_schema.type` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "test"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/invalid JSON type: test/
--- error_code chomp
400



=== TEST 18: add route (test request validation `body_schema.enum` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "string",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": "test-enum"
                                    }
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/table expected, got string/
--- error_code chomp
400



=== TEST 19: add route (test request validation `body_schema.enum` success)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "string",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 20: add route (test request validation `body_schema.required` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": "test-required"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/table expected, got string/
--- error_code chomp
400



=== TEST 21: add route (test request validation `body_schema.required` success)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 22: add route (test request validation `header_schema`)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "required": ["required_payload"],
                                "properties": {
                                    "required_payload": {"type": "string"},
                                    "boolean_payload": {"type": "boolean"},
                                    "timeouts": {
                                       "type": "integer",
                                        "minimum": 1,
                                        "maximum": 254,
                                        "default": 3
                                    },
                                    "req_headers": {
                                        "type": "array",
                                        "minItems": 1,
                                        "items": {
                                            "type": "string"
                                        }
                                    }
                                }
                            }
                        }
                    },]] .. [[
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 23: add route (test request validation `header_schema.type` is object)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 24: add route (test request validation `header_schema.type` is array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "array"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 25: add route (test request validation `header_schema.type` is string)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "string"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 26: add route (test request validation `header_schema.type` is number)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "number"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 27: add route (test request validation `header_schema.type` is integer)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "integer"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 28: add route (test request validation `header_schema.type` is table)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "table"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 29: add route (test request validation `header_schema.type` is function)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "function"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 30: add route (test request validation `header_schema.type` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "test"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/invalid JSON type: test/
--- error_code chomp
400



=== TEST 31: add route (test request validation `header_schema.enum` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "string",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": "test-enum"
                                    }
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/table expected, got string/
--- error_code chomp
400



=== TEST 32: add route (test request validation `header_schema.enum` success)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "string",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 33: add route (test request validation `header_schema.required` failure)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": "test-required"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/table expected, got string/
--- error_code chomp
400



=== TEST 34: add route (test request validation `header_schema.required` success)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
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



=== TEST 35: add route (test request validation `header_schema.required` success with custom reject message)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            },
                            "rejected_msg": "customize reject message for header_schema.required"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]])
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



=== TEST 36: use empty header to hit `header_schema.required with custom reject message` rule
--- request
GET /opentracing
--- error_code: 400
--- response_body chomp
customize reject message for header_schema.required
--- error_log eval
qr/schema validation failed/



=== TEST 37: use bad header value to hit `header_schema.required with custom reject message` rule
--- request
GET /opentracing
--- more_headers
test: abc
--- error_code: 400
--- response_body chomp
customize reject message for header_schema.required
--- error_log eval
qr/schema validation failed/



=== TEST 38: pass `header_schema.required with custom reject message` rule
--- request
GET /opentracing
--- more_headers
test: a
--- error_code: 200
--- response_body eval
qr/opentracing/



=== TEST 39: add route (test request validation `body_schema.required` success with custom reject message)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            },
                            "rejected_msg": "customize reject message for body_schema.required"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]])
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



=== TEST 40: use empty body to hit `body_schema.required with custom reject message` rule
--- request
GET /opentracing
--- error_code: 400
--- response_body chomp
customize reject message for body_schema.required



=== TEST 41: use bad body value to hit `body_schema.required with custom reject message` rule
--- request
POST /opentracing
{"test":"abc"}
--- error_code: 400
--- response_body chomp
customize reject message for body_schema.required
--- error_log eval
qr/schema validation failed/



=== TEST 42: pass `body_schema.required with custom reject message` rule
--- request
POST /opentracing
{"test":"a"}
--- error_code: 200
--- response_body eval
qr/opentracing/



=== TEST 43: add route (test request validation `header_schema.required` failure with custom reject message)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            },
                            "rejected_msg": "customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message customize reject message"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/string too long/
--- error_code: 400



=== TEST 44: add route (test request validation schema with custom reject message only)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "rejected_msg": "customize reject message"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/object matches none of the required/
--- error_code: 400



=== TEST 45: add route (test request validation `body_schema.required` success with custom reject code)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            },
                            "rejected_code": 505
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]])
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



=== TEST 46: use empty body to hit custom rejected code rule
--- request
GET /opentracing
--- error_code: 505



=== TEST 47: use bad body value to hit custom rejected code rule
--- request
POST /opentracing
{"test":"abc"}
--- error_code: 505
--- error_log eval
qr/schema validation failed/



=== TEST 48: pass custom rejected code rule
--- request
POST /opentracing
{"test":"a"}
--- error_code: 200
--- response_body eval
qr/opentracing/



=== TEST 49: add route (test request validation `header_schema.required` failure with custom reject code)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "header_schema": {
                                "type": "object",
                                "properties": {
                                    "test": {
                                        "type": "string",
                                        "enum": ["a", "b", "c"]
                                    }
                                },
                                "required": ["test"]
                            },
                            "rejected_code": 10000
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/expected 10000 to be at most 599/
--- error_code: 400



=== TEST 50: add route (test request validation schema with custom reject code only)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "rejected_code": 505
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/plugin/request/validation"
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/object matches none of the required/
--- error_code: 400



=== TEST 51: add route for urlencoded post data validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "request-validation": {
                            "body_schema": {
                                "type": "object",
                                "required": ["required_payload"],
                                "properties": {
                                    "required_payload": {"type": "string"}
                                },
                                "rejected_msg": "customize reject message"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]])
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



=== TEST 52: test urlencoded post data
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- request eval
"POST /echo
" . "a=b&" x 101 . "required_payload=101-hello"
--- response_body eval
qr/101-hello/



=== TEST 53: test urlencoded post data with charset header
--- more_headers
Content-Type: application/x-www-form-urlencoded; charset=utf-8
--- request eval
"POST /echo
" . "a=b&" x 101 . "required_payload=101-hello"
--- response_body eval
qr/101-hello/
