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

=== TEST 1: set route (default grpc web proxy route)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/grpc/web/*",
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



=== TEST 2: Proxy unary request using APISIX gRPC-Web plugin
--- exec
node ./t/plugin/grpc-web/client.js BIN UNARY
node ./t/plugin/grpc-web/client.js TEXT UNARY
--- response_body
{"name":"hello","path":"/hello"}
{"name":"hello","path":"/hello"}



=== TEST 3: Proxy server-side streaming request using APISIX gRPC-Web plugin
--- exec
node ./t/plugin/grpc-web/client.js BIN STREAM
node ./t/plugin/grpc-web/client.js TEXT STREAM
--- response_body
{"name":"hello","path":"/hello"}
{"name":"world","path":"/world"}
{"name":"hello","path":"/hello"}
{"name":"world","path":"/world"}



=== TEST 4: test options request
--- request
OPTIONS /grpc/web/a6.RouteService/GetRoute
--- error_code: 204
--- response_headers
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: content-type,x-grpc-web,x-user-agent,grpc-accept-encoding
Access-Control-Allow-Origin: *



=== TEST 5: test non-options request
--- request
GET /grpc/web/a6.RouteService/GetRoute
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
--- error_log
request method: `GET` invalid



=== TEST 6: test non gRPC Web MIME type request
--- request
POST /grpc/web/a6.RouteService/GetRoute
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
Content-Type: application/json
--- error_log
request Content-Type: `application/json` invalid



=== TEST 7: set route (absolute match)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/grpc/web2/a6.RouteService/GetRoute",
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



=== TEST 8: test route (absolute match)
--- request
POST /grpc/web2/a6.RouteService/GetRoute
--- more_headers
Content-Type: application/grpc-web
--- error_code: 400
--- response_headers
Access-Control-Allow-Origin: *
Content-Type: application/grpc-web
--- error_log
routing configuration error, grpc-web plugin only supports `prefix matching` pattern routing



=== TEST 9: set route (with cors plugin)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/grpc/web/*",
                upstream = {
                    scheme = "grpc",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:50001"] = 1
                    }
                },
                plugins = {
                    ["grpc-web"] = {},
                    cors = {
                        allow_origins = "http://test.com",
                        allow_methods = "POST,OPTIONS",
                        allow_headers = "application/grpc-web",
                        expose_headers = "application/grpc-web",
                        max_age = 5,
                        allow_credential = true
                    }
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



=== TEST 10: don't override Access-Control-Allow-Origin header in response
--- request
POST /grpc/web/a6.RouteService/GetRoute
{}
--- more_headers
Origin: http://test.com
Content-Type: application/grpc-web
--- response_headers
Access-Control-Allow-Origin: http://test.com
Content-Type: application/grpc-web

=== TEST 11: grpc-web access control expose headers for non grpc servers that don't implement grpc-web
--- request
POST /grpc/web/a6.RouteService/GetRoute
{}
--- more_headers
Origin: http://test.com
Content-Type: application/grpc-web
--- response_headers
Access-Control-Allow-Origin: http://test.com
Content-Type: application/grpc-web
Access-Control-Expose-Headers: grpc-status,grpc-message

