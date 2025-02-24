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



=== TEST 2: Proxy unary request using APISIX with trailers gRPC-Web plugin
Status should be printed at most once per request, otherwise this would be out of specification.
--- exec
node ./t/plugin/grpc-web/client.js BIN UNARY
node ./t/plugin/grpc-web/client.js TEXT UNARY
--- response_body
Status: { code: 0, details: '', metadata: {} }
{"name":"hello","path":"/hello"}
Status: { code: 0, details: '', metadata: {} }
{"name":"hello","path":"/hello"}



=== TEST 3: Proxy server-side streaming request using APISIX with trailers gRPC-Web plugin
--- exec
node ./t/plugin/grpc-web/client.js BIN STREAM
node ./t/plugin/grpc-web/client.js TEXT STREAM
--- response_body
{"name":"hello","path":"/hello"}
{"name":"world","path":"/world"}
Status: { code: 0, details: '', metadata: {} }
{"name":"hello","path":"/hello"}
{"name":"world","path":"/world"}
Status: { code: 0, details: '', metadata: {} }



=== TEST 4: test options request
--- request
OPTIONS /grpc/web/a6.RouteService/GetRoute
--- error_code: 204
--- response_headers
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: content-type,x-grpc-web,x-user-agent
Access-Control-Allow-Origin: *



=== TEST 5: test non-options request
--- request
GET /grpc/web/a6.RouteService/GetRoute
--- error_code: 405
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
Content-Type: text/html
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
Content-Type: text/html
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
--- exec
curl -iv --location 'http://127.0.0.1:1984/grpc/web/a6.RouteService/GetRoute' \
--header 'Origin: http://test.com' \
--header 'Content-Type: application/grpc-web-text' \
--data-raw 'AAAAAAcKBXdvcmxkCgo='
--- response_body eval
qr/HTTP\/1.1 200 OK/ and qr/Access-Control-Allow-Origin: http:\/\/test.com/



=== TEST 11: check for Access-Control-Expose-Headers header in response
--- exec
curl -iv --location 'http://127.0.0.1:1984/grpc/web/a6.RouteService/GetRoute' \
--header 'Origin: http://test.com' \
--header 'Content-Type: application/grpc-web-text' \
--data-raw 'AAAAAAcKBXdvcmxkCgo='
--- response_body eval
qr/Access-Control-Expose-Headers: grpc-message,grpc-status/ and qr/Access-Control-Allow-Origin: http:\/\/test.com/



=== TEST 12: verify trailers in response
According to the gRPC documentation, the grpc-web proxy should not retain trailers received from upstream when
forwarding them, as the reference implementation envoy does, so the current test case is status quo rather
than "correct", which is not expected to have an impact since browsers ignore trailers.
Currently there is no API or hook point available in nginx/lua-nginx-module to remove specified trailers
on demand (grpc_hide_header can do it but it affects the grpc proxy), and some nginx patches may be needed
to allow for code-controlled removal of the trailer at runtime.
When we implement that, this use case will be removed.
--- exec
curl -iv --location 'http://127.0.0.1:1984/grpc/web/a6.RouteService/GetRoute' \
--header 'Content-Type: application/grpc-web+proto' \
--header 'X-Grpc-Web: 1' \
--data-binary '@./t/plugin/grpc-web/req.bin'
--- response_body eval
qr/grpc-status:0\x0d\x0agrpc-message:/



=== TEST 13: confg default response route
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



=== TEST 14: check header in default response
--- request
OPTIONS /grpc/web/a6.RouteService/GetRoute
--- error_code: 204
--- response_headers
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: content-type,x-grpc-web,x-user-agent
Access-Control-Allow-Origin: *
Access-Control-Expose-Headers: grpc-message,grpc-status



=== TEST 15: Custom configuration routing
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
                    ["grpc-web"] = {
                        cors_allow_headers = "grpc-accept-encoding"
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



=== TEST 16: check header in default response
--- request
OPTIONS /grpc/web/a6.RouteService/GetRoute
--- error_code: 204
--- response_headers
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: grpc-accept-encoding
Access-Control-Allow-Origin: *
Access-Control-Expose-Headers: grpc-message,grpc-status
