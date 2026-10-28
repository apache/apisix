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

        location /ka/ {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /svl/ {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /sva/ {
            content_by_lua_block {
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location = / {
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



=== TEST 10: set routes whose plugins rewrite the request after matching
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/consumers", ngx.HTTP_PUT, {
                username = "jack",
                plugins = {
                    ["key-auth"] = { key = "auth-one" },
                },
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local routes = {
                {
                    id = "ka",
                    uri = "/ka/*",
                    plugins = {
                        ["key-auth"] = { hide_credentials = true },
                    },
                },
                {
                    id = "svl",
                    uri = "/svl/*",
                    plugins = {
                        ["serverless-pre-function"] = {
                            phase = "access",
                            functions = {
                                "return function() ngx.req.set_uri('/svl/changed') end",
                            },
                        },
                    },
                },
                {
                    id = "sva",
                    uri = "/sva/*",
                    plugins = {
                        ["serverless-pre-function"] = {
                            phase = "access",
                            functions = {
                                "return function() ngx.req.set_uri_args('added=1') end",
                            },
                        },
                    },
                },
                {
                    id = "api",
                    uri = "/api/*",
                },
                {
                    id = "root",
                    uri = "/",
                },
            }

            for _, route in ipairs(routes) do
                route.upstream = {
                    nodes = { ["127.0.0.1:1980"] = 1 },
                    type = "roundrobin",
                }

                code, body = t("/apisix/admin/routes/" .. route.id,
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



=== TEST 11: hidden query credential is removed from a dot segment request
--- request
GET /ka/./x?apikey=auth-one&a=1
--- response_body
request-uri=/ka/x?a=1



=== TEST 12: path set by a plugin is forwarded
--- request
GET /svl/./x
--- response_body
request-uri=/svl/changed



=== TEST 13: args set by a plugin are forwarded
--- request
GET /sva/./x?b=2
--- response_body
request-uri=/sva/x?added=1



=== TEST 14: single dot segment forwards the matched path
--- request
GET /api/./x
--- response_body
request-uri=/api/x



=== TEST 15: path cut at "#" forwards the matched path
--- raw_request eval
"GET /admin/..#x HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
--- response_body
request-uri=/



=== TEST 16: decoded control char in the matched path is escaped
--- request
GET /api/./a%0Ab
--- response_body
request-uri=/api/a%0Ab



=== TEST 17: trailing slash is kept with delete_uri_tail_slash
--- yaml_config
apisix:
    node_listen: 1984
    delete_uri_tail_slash: true
    router:
        http: 'radixtree_uri'
--- request
GET /api/./x/
--- response_body
request-uri=/api/x/



=== TEST 18: servlet mode forwards the matched path
--- yaml_config
apisix:
    node_listen: 1984
    normalize_uri_like_servlet: true
    router:
        http: 'radixtree_uri'
--- request
GET /api/./x
--- response_body
request-uri=/api/x



=== TEST 19: remove the routes and the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, id in ipairs({"ka", "svl", "sva", "api", "root"}) do
                local code, body = t("/apisix/admin/routes/" .. id, ngx.HTTP_DELETE)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end

            local code, body = t("/apisix/admin/consumers/jack", ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed
