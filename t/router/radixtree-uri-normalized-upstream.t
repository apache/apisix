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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->upstream_server_config) {
        $block->set_value("upstream_server_config", <<'_EOC_');
        location /admin/ {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /api/ {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location = /fixed {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }
_EOC_
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set routes with and without auth on the same upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local routes = {
                {
                    id = "admin",
                    uri = "/admin/*",
                    plugins = {
                        ["key-auth"] = {},
                    },
                },
                {
                    id = "api",
                    uri = "/api/*",
                },
                {
                    id = "rewrite",
                    uri = "/rewrite/*",
                    plugins = {
                        ["proxy-rewrite"] = {
                            uri = "/fixed",
                        },
                    },
                },
            }

            for _, route in ipairs(routes) do
                route.upstream = {
                    nodes = { ["127.0.0.1:1980"] = 1 },
                    type = "roundrobin",
                }

                local code, body = t("/apisix/admin/routes/" .. route.id,
                    ngx.HTTP_PUT, route)
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



=== TEST 2: route with key-auth requires an API key
--- request
GET /admin/x
--- error_code: 401
--- response_body
{"message":"Missing API key in request"}



=== TEST 3: encoded slash dot segment forwards the matched path
--- request
GET /admin/..%2Fapi/x
--- response_body
request-uri=/api/x



=== TEST 4: encoded dot segment forwards the matched path with args
--- request
GET /admin/%2e%2e/api/x?a=1&b=%2F
--- response_body
request-uri=/api/x?a=1&b=%2F



=== TEST 5: plain dot segment forwards the matched path
--- request
GET /admin/../api/x
--- response_body
request-uri=/api/x



=== TEST 6: merged slashes alone are forwarded unchanged
--- request
GET /api/https://example.com//x
--- response_body
request-uri=/api/https://example.com//x



=== TEST 7: encoded path without normalization is forwarded unchanged
--- request
GET /api/a%2Fb%20c?x=1
--- response_body
request-uri=/api/a%2Fb%20c?x=1



=== TEST 8: proxy-rewrite uri still takes precedence
--- request
GET /rewrite/a/..%2Fb
--- response_body
request-uri=/fixed



=== TEST 9: remove the routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, id in ipairs({"admin", "api", "rewrite"}) do
                local code, body = t("/apisix/admin/routes/" .. id, ngx.HTTP_DELETE)
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
