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

no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set proto and routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local code, body = t('/apisix/admin/protos/1', ngx.HTTP_PUT, json.encode({
                content = [[
                    syntax = "proto3";
                    package helloworld;
                    service Greeter {
                        rpc SayHello (HelloRequest) returns (HelloReply) {}
                        rpc GetErrResp (HelloRequest) returns (HelloReply) {}
                        rpc Plus (PlusRequest) returns (PlusReply) {}
                        rpc SayMultipleHello (MultipleHelloRequest) returns (MultipleHelloReply) {}
                        rpc SayHelloServerStream (HelloRequest) returns (stream HelloReply) {}
                        rpc SayHelloClientStream (stream HelloRequest) returns (HelloReply) {}
                    }
                    enum Gender {
                        GENDER_UNKNOWN = 0;
                        GENDER_MALE = 1;
                        GENDER_FEMALE = 2;
                    }
                    message Person {
                        string name = 1;
                        int32 age = 2;
                    }
                    message HelloRequest {
                        string name = 1;
                        repeated string items = 2;
                        Gender gender = 3;
                        Person person = 4;
                    }
                    message HelloReply {
                        string message = 1;
                        repeated string items = 2;
                        Gender gender = 3;
                    }
                    message PlusRequest {
                        int64 a = 1;
                        int64 b = 2;
                    }
                    message PlusReply {
                        int64 result = 1;
                    }
                    message MultipleHelloRequest {
                        string name = 1;
                        repeated string items = 2;
                        repeated Gender genders = 3;
                        repeated Person persons = 4;
                    }
                    message MultipleHelloReply {
                        string message = 1;
                        repeated string items = 2;
                        repeated Gender genders = 3;
                    }
                    message ErrorDetail {
                        int64 code = 1;
                        string message = 2;
                        string type = 3;
                    }
                ]]
            }))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local routes = {
                {"/protojson/plus", "Plus", {protojson = true}},
                {"/legacy/plus", "Plus", {}},
                {"/protojson/hello", "SayHello", {protojson = true}},
                {"/legacy/hello", "SayHello", {}},
                {"/protojson/multiple", "SayMultipleHello", {protojson = true}},
                {"/protojson/error", "GetErrResp", {protojson = true,
                    show_status_in_body = true, status_detail_type = "helloworld.ErrorDetail"}},
                {"/protojson/error-untyped", "GetErrResp", {protojson = true,
                    show_status_in_body = true}},
                {"/protojson/error-flat", "GetErrResp", {protojson = true,
                    show_status_in_body = true, status_detail_type = "helloworld.Missing",
                    error_response_format = "flat"}},
                {"/protojson/server-stream", "SayHelloServerStream", {protojson = true}},
                {"/protojson/client-stream", "SayHelloClientStream", {protojson = true}},
                {"/protojson/request-limit", "SayHello", {protojson = true,
                    max_req_body_size = 32}},
                {"/legacy/request-limit", "SayHello", {max_req_body_size = 32}},
                {"/protojson/response-limit", "SayHello", {protojson = true,
                    max_resp_body_size = 8}},
            }
            for i, route in ipairs(routes) do
                local conf = route[3]
                conf.proto_id = "1"
                conf.service = "helloworld.Greeter"
                conf.method = route[2]
                code, body = t('/apisix/admin/routes/' .. i, ngx.HTTP_PUT, json.encode({
                    uri = route[1],
                    plugins = {["grpc-transcode"] = conf},
                    upstream = {
                        scheme = "grpc",
                        type = "roundrobin",
                        nodes = {["127.0.0.1:10051"] = 1},
                    },
                }))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: int64 beyond 2^53 is exact
--- request
POST /protojson/plus
{"a":"9007199254740993","b":"1"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"result":"9007199254740994"}



=== TEST 3: query string scalars
--- request
GET /protojson/plus?a=1&b=2
--- response_body chomp
{"result":"3"}



=== TEST 4: legacy and ProtoJSON routes sharing a proto keep their own options
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            for _, path in ipairs({"/protojson/plus", "/legacy/plus", "/protojson/plus"}) do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. path .. "?a=1&b=2"
                local res = assert(http.new():request_uri(uri, {keepalive = false}))
                ngx.say(res.body)
            end
        }
    }
--- response_body
{"result":"3"}
{"result":3}
{"result":"3"}



=== TEST 5: default values are omitted, legacy output is unchanged
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            for _, path in ipairs({"/protojson/hello", "/legacy/hello"}) do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. path
                local res = assert(http.new():request_uri(uri, {
                    method = "POST",
                    body = [[{"name":"x"}]],
                    headers = {["Content-Type"] = "application/json"},
                    keepalive = false,
                }))
                ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
            end
        }
    }
--- response_body
200 {"message":"Hello x"}
200 {"gender":"GENDER_UNKNOWN","items":[],"message":"Hello x"}



=== TEST 6: nested message, enum and repeated fields
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/hello"
            local res = assert(http.new():request_uri(uri, {
                method = "POST",
                body = [[{"name":"x","items":["a","b"],"gender":"GENDER_FEMALE",
                          "person":{"name":"p","age":3},"unknown":true}]],
                headers = {["Content-Type"] = "application/json"},
                keepalive = false,
            }))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
200 {"gender":"GENDER_FEMALE","items":["a","b"],"message":"Hello x, name: p, age: 3"}



=== TEST 7: repeated enums and messages, enum by number
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/multiple"
            local res = assert(http.new():request_uri(uri, {
                method = "POST",
                body = [[{"name":"x","genders":["GENDER_MALE",2],
                          "persons":[{"name":"a","age":1},{"name":"b"}]}]],
                headers = {["Content-Type"] = "application/json"},
                keepalive = false,
            }))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
200 {"genders":["GENDER_MALE","GENDER_FEMALE"],"message":"Hello x, name: a, age: 1, name: b"}



=== TEST 8: invalid 64-bit integer is rejected with its location
--- request
POST /protojson/plus
{"a":"abc","b":"1"}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"transcode request failed"}
--- error_log
ProtoJSON .helloworld.PlusRequest.a: invalid decimal 64-bit integer



=== TEST 9: invalid JSON is rejected, not read from other sources
--- request
POST /protojson/plus?a=1&b=2
{"a":
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"transcode request failed"}
--- error_log
grpc-transcode invalid request: invalid JSON request



=== TEST 10: typed status details follow the ProtoJSON mapping
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/error"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
503 {"error":{"code":14,"details":[{"code":"1","message":"The server is out of service","type":"service"}],"message":"Out of service"}}



=== TEST 11: untyped status details keep the type URL and a base64 value
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                        "/protojson/error-untyped"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
503 {"error":{"code":14,"details":[{"@type":"type.googleapis.com/helloworld.ErrorDetail","value":"CAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U="}],"message":"Out of service"}}



=== TEST 12: undecodable status details fall back to code and message, flat body
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/error-flat"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
503 {"code":14,"message":"Out of service"}



=== TEST 13: set binary proto and route for EchoStruct
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local content = t.read_file("t/grpc_server_example/echo.pb")
            local code, body = t.test('/apisix/admin/protos/2', ngx.HTTP_PUT,
                json.encode({content = ngx.encode_base64(content)}))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t.test('/apisix/admin/routes/100', ngx.HTTP_PUT, json.encode({
                uri = "/protojson/struct",
                plugins = {["grpc-transcode"] = {
                    proto_id = "2",
                    service = "echo.Echo",
                    method = "EchoStruct",
                    protojson = true,
                }},
                upstream = {
                    scheme = "grpc",
                    type = "roundrobin",
                    nodes = {["127.0.0.1:10051"] = 1},
                },
            }))
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: Struct round trip keeps null, false, zero, empty object and empty array
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local body = [=[{"data":{"active":false,"count":0,"nothing":null,
                            "items":[1,"x",{},[]],"nested":{"deep":true}}}]=]
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/struct"
            local res = assert(http.new():request_uri(uri, {
                method = "POST",
                body = body,
                headers = {["Content-Type"] = "application/json"},
                keepalive = false,
            }))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
200 {"data":{"active":false,"count":0,"items":[1,"x",{},[]],"nested":{"deep":true},"nothing":null}}



=== TEST 15: streaming RPC answered by a single message is transcoded
--- request
POST /protojson/client-stream
{"name":"x"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"Hello x!"}



=== TEST 16: several response messages abort the response instead of producing broken JSON
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                        "/protojson/server-stream"
            local res, err = http.new():request_uri(uri, {
                method = "POST",
                body = [[{"name":"x"}]],
                headers = {["Content-Type"] = "application/json"},
                keepalive = false,
            })
            ngx.say(res and ("completed: " .. res.status) or "aborted")
        }
    }
--- response_body
aborted
--- error_log
transform response error: invalid or unsupported gRPC frame



=== TEST 17: request body limit applies to both modes
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            for _, path in ipairs({"/protojson/request-limit", "/legacy/request-limit"}) do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. path
                local res = assert(http.new():request_uri(uri, {
                    method = "POST",
                    body = [[{"name":"a name longer than thirty-two bytes"}]],
                    headers = {["Content-Type"] = "application/json"},
                    keepalive = false,
                }))
                ngx.say(res.status)
            end
        }
    }
--- response_body
413
413
--- error_log
transform request error: invalid request body



=== TEST 18: oversized response aborts instead of being truncated
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                        "/protojson/response-limit"
            local res, err = http.new():request_uri(uri, {
                method = "POST",
                body = [[{"name":"a name longer than the limit"}]],
                headers = {["Content-Type"] = "application/json"},
                keepalive = false,
            })
            ngx.say(res and ("completed: " .. res.status) or "aborted")
        }
    }
--- response_body
aborted
--- error_log
response body exceeds max_resp_body_size



=== TEST 19: schema validation of the new attributes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.grpc-transcode")
            local base = {proto_id = "1", service = "helloworld.Greeter", method = "Plus"}
            for _, extra in ipairs({
                {protojson = "yes"},
                {any_empty_format = "other"},
                {error_response_format = "other"},
                {max_req_body_size = 0},
            }) do
                local conf = {}
                for k, v in pairs(base) do conf[k] = v end
                for k, v in pairs(extra) do conf[k] = v end
                local ok, err = plugin.check_schema(conf)
                ngx.say(ok and "accepted" or err)
            end
        }
    }
--- response_body
property "protojson" validation failed: wrong type: expected boolean, got string
property "any_empty_format" validation failed: matches none of the enum values
property "error_response_format" validation failed: matches none of the enum values
property "max_req_body_size" validation failed: expected 0 to be at least 1



=== TEST 20: set proto and route for request value checks
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local code, body = t('/apisix/admin/protos/3', ngx.HTTP_PUT, json.encode({
                content = [[
                    syntax = "proto3";
                    package validation;
                    service Checker {
                        rpc Check (CheckRequest) returns (CheckReply) {}
                    }
                    enum Color {
                        COLOR_UNSPECIFIED = 0;
                        COLOR_RED = 1;
                    }
                    message CheckRequest {
                        int32 small = 1;
                        uint32 count = 2;
                        sint32 delta = 3;
                        fixed32 mask = 4;
                        float ratio = 5;
                        string label = 6;
                        Color color = 7;
                        string user_name = 8;
                        oneof target {
                            string id = 9;
                            int32 index = 10;
                        }
                        map<int32, string> tags = 11;
                    }
                    message CheckReply {}
                ]]
            }))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/101', ngx.HTTP_PUT, json.encode({
                uri = "/protojson/check",
                plugins = {["grpc-transcode"] = {
                    proto_id = "3",
                    service = "validation.Checker",
                    method = "Check",
                    protojson = true,
                }},
                upstream = {
                    scheme = "grpc",
                    type = "roundrobin",
                    nodes = {["127.0.0.1:10051"] = 1},
                },
            }))
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: request values are checked against the field type before encoding
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/check"
            for _, body in ipairs({
                '{"small": 1.5}',
                '{"small": 3e10}',
                '{"small": true}',
                '{"count": -1}',
                '{"delta": 2147483648}',
                '{"mask": "1.5"}',
                '{"color": 1.5}',
                '{"color": "COLOR_BLUE"}',
                '{"color": "1"}',
                '{"ratio": 1e300}',
                '{"label": 123}',
                '{"user_name": "a", "userName": "b"}',
                '{"id": "a", "index": 1}',
                '{"tags": {"x": "a"}}',
                '{"tags": {"1": 5}}',
            }) do
                local res = assert(http.new():request_uri(uri, {
                    method = "POST",
                    body = body,
                    headers = {["Content-Type"] = "application/json"},
                    keepalive = false,
                }))
                ngx.say(res.status, " ", body)
            end
        }
    }
--- response_body
400 {"small": 1.5}
400 {"small": 3e10}
400 {"small": true}
400 {"count": -1}
400 {"delta": 2147483648}
400 {"mask": "1.5"}
400 {"color": 1.5}
400 {"color": "COLOR_BLUE"}
400 {"color": "1"}
400 {"ratio": 1e300}
400 {"label": 123}
400 {"user_name": "a", "userName": "b"}
400 {"id": "a", "index": 1}
400 {"tags": {"x": "a"}}
400 {"tags": {"1": 5}}
--- error_log
ProtoJSON .validation.CheckRequest.small: invalid 32-bit integer
ProtoJSON .validation.CheckRequest.small: 32-bit integer out of range
ProtoJSON .validation.CheckRequest.count: 32-bit integer out of range
ProtoJSON .validation.CheckRequest.delta: 32-bit integer out of range
ProtoJSON .validation.CheckRequest.mask: invalid 32-bit integer
ProtoJSON .validation.CheckRequest.color: enum must be a value name or a 32-bit integer
ProtoJSON .validation.CheckRequest.color: unknown enum value name
ProtoJSON .validation.CheckRequest.ratio: floating-point value out of range
ProtoJSON .validation.CheckRequest.label: expected string
ProtoJSON .validation.CheckRequest.user_name: field is set twice, as user_name and userName
ProtoJSON .validation.CheckRequest.index: oneof target is already set by id
ProtoJSON .validation.CheckRequest.tags: invalid integer map key
ProtoJSON .validation.CheckRequest.tags: expected string



=== TEST 22: 32-bit integers written as strings or with an exponent, enum numbers in the query
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")
            local base = "http://127.0.0.1:" .. ngx.var.server_port .. "/protojson/hello"
            for _, body in ipairs({
                [[{"name":"x","person":{"name":"p","age":"7"}}]],
                [[{"name":"x","person":{"name":"p","age":1e2}}]],
                [[{"name":"x","person":{"name":"p","age":2147483647}}]],
            }) do
                local res = assert(http.new():request_uri(base, {
                    method = "POST",
                    body = body,
                    headers = {["Content-Type"] = "application/json"},
                    keepalive = false,
                }))
                ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
            end
            local res = assert(http.new():request_uri(base .. "?name=x&gender=2",
                                                      {keepalive = false}))
            ngx.say(res.status, " ", json.encode((json.decode(res.body, 1, json.null))))
        }
    }
--- response_body
200 {"message":"Hello x, name: p, age: 7"}
200 {"message":"Hello x, name: p, age: 100"}
200 {"message":"Hello x, name: p, age: 2147483647"}
200 {"gender":"GENDER_FEMALE","message":"Hello x"}



=== TEST 23: request body limit applies to form bodies in both modes
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            for _, path in ipairs({"/protojson/request-limit", "/legacy/request-limit"}) do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. path
                for _, body in ipairs({"name=x", "name=a+name+longer+than+thirty-two+bytes"}) do
                    local res = assert(http.new():request_uri(uri, {
                        method = "POST",
                        body = body,
                        headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
                        keepalive = false,
                    }))
                    ngx.say(res.status)
                end
            end
        }
    }
--- response_body
200
413
200
413
--- error_log
grpc-transcode invalid request: request body too large
