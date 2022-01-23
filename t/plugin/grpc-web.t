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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route (default grpc web proxy route)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/grpc/*",
                upstream = {
                    scheme = "grpc",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:50001"] = 1
                    }
                },
                plugins = {
                    ["grpc-web"] = {}
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: Flush all data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN FLUSH
node ./t/plugin/grpc-web/client.js TEXT FLUSH
--- response_body
[]
[]



=== TEST 3: Insert first data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN POST 1 route01 path01
node ./t/plugin/grpc-web/client.js TEXT POST 1 route01 path01
--- response_body
[["1",{"name":"route01","path":"path01"}]]
[["1",{"name":"route01","path":"path01"}]]



=== TEST 4: Update data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN PUT 1 route01 hello
node ./t/plugin/grpc-web/client.js TEXT PUT 1 route01 hello
--- response_body
[["1",{"name":"route01","path":"hello"}]]
[["1",{"name":"route01","path":"hello"}]]



=== TEST 5: Insert second data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN POST 2 route02 path02
node ./t/plugin/grpc-web/client.js TEXT POST 2 route02 path02
--- response_body
[["1",{"name":"route01","path":"hello"}],["2",{"name":"route02","path":"path02"}]]
[["1",{"name":"route01","path":"hello"}],["2",{"name":"route02","path":"path02"}]]



=== TEST 6: Insert third data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN POST 3 route03 path03
node ./t/plugin/grpc-web/client.js TEXT POST 3 route03 path03
--- response_body
[["1",{"name":"route01","path":"hello"}],["2",{"name":"route02","path":"path02"}],["3",{"name":"route03","path":"path03"}]]
[["1",{"name":"route01","path":"hello"}],["2",{"name":"route02","path":"path02"}],["3",{"name":"route03","path":"path03"}]]



=== TEST 7: Delete first data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN DEL 3
node ./t/plugin/grpc-web/client.js TEXT DEL 2
--- response_body
[["1",{"name":"route01","path":"hello"}],["2",{"name":"route02","path":"path02"}]]
[["1",{"name":"route01","path":"hello"}]]



=== TEST 8: Get second data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN GET 1
node ./t/plugin/grpc-web/client.js TEXT GET 1
--- response_body
{"name":"route01","path":"hello"}
{"name":"route01","path":"hello"}



=== TEST 9: Get all data through APISIX gRPC-Web Proxy
--- exec
node ./t/plugin/grpc-web/client.js BIN all
node ./t/plugin/grpc-web/client.js TEXT all
--- response_body
[["1",{"name":"route01","path":"hello"}]]
[["1",{"name":"route01","path":"hello"}]]



=== TEST 10: test options request
--- request
OPTIONS /grpc/a6.RouteService/GetAll
--- error_code: 204
--- response_headers
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: content-type,x-grpc-web,x-user-agent
Access-Control-Allow-Origin: *



=== TEST 11: test non-options request
--- request
GET /grpc/a6.RouteService/GetAll
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
--- error_log
request method: `GET` invalid



=== TEST 12: test non gRPC Web MIME type request
--- request
POST /grpc/a6.RouteService/GetAll
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
Content-Type: application/json
--- error_log
request Content-Type: `application/json` invalid



=== TEST 13: set route (absolute match)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/grpc2/a6.RouteService/GetAll",
                upstream = {
                    scheme = "grpc",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:50001"] = 1
                    }
                },
                plugins = {
                    ["grpc-web"] = {}
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: test route (absolute match)
--- request
POST /grpc2/a6.RouteService/GetAll
--- more_headers
Content-Type: application/grpc-web
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
Content-Type: application/grpc-web
--- error_log
routing configuration error, grpc-web plugin only supports `prefix matching` pattern routing
