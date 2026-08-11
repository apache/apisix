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

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    match_uri_encoded_slash: true
    router:
        http: 'radixtree_uri_with_parameter'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }

    # An echo endpoint on the fake upstream that returns the request line it
    # received, so a test can assert on the URI actually forwarded upstream.
    if (!$block->upstream_server_config) {
        $block->set_value("upstream_server_config", <<'_EOC_');
        location /echo/ {
            content_by_lua_block {
                ngx.say(ngx.var.request_uri)
            }
        }
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: set routes (path parameter, trailing slash and root)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local routes = {
                {id = 1, uri = "/v1/:id/products/:type/list"},
                {id = 2, uri = "/trailing/:name/"},
                {id = 3, uri = "/"},
            }
            for _, r in ipairs(routes) do
                local code, body = t("/apisix/admin/routes/" .. r.id,
                    ngx.HTTP_PUT,
                    {
                        uri = r.uri,
                        upstream = {
                            nodes = {["127.0.0.1:1980"] = 1},
                            type = "roundrobin",
                        },
                    }
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: encoded slash (%2F) in a path parameter is matched (not a separator)
--- request
GET /v1/te%2Fst/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 3: lowercase encoded slash (%2f) is matched
--- request
GET /v1/te%2fst/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 4: a serial number with multiple encoded slashes is matched
--- request
GET /v1/2024%2F01%2F0001/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 5: request without encoded slash still matches as before
--- request
GET /v1/test/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 6: other percent-encodings are still decoded (%41 -> A), still matches
--- request
GET /v1/te%41st/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 7: trailing slash is preserved, so the trailing-slash route matches
--- request
GET /trailing/a%2Fb/
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 8: a request that also needs dot-segment normalization falls back to $uri
--- request
GET /x%2Fy/../..
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 9: an encoded dot segment (%2e) also falls back to $uri
--- request
GET /a%2Fb/%2e%2e/%2e%2e
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 10: an encoded slash only in the query string does not rebuild the path
--- request
GET /?next=%2Fadmin
--- error_code: 404
--- error_log
undefined path in test server, uri: /?next=%2Fadmin



=== TEST 11: set a route with a plugin that logs the uri it observes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/10",
                ngx.HTTP_PUT,
                {
                    uri = "/pv/:id/list",
                    plugins = {
                        ["serverless-pre-function"] = {
                            phase = "rewrite",
                            functions = {
                                "return function(_, ctx) ngx.log(ngx.WARN, "
                                .. "'match_uri_view uri=', ctx.var.uri, "
                                .. "' param=', ctx.var.uri_param_id) end"
                            },
                        },
                    },
                    upstream = {
                        nodes = {["127.0.0.1:1980"] = 1},
                        type = "roundrobin",
                    },
                }
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



=== TEST 12: the encoded slash is match-only: plugins see the normalized uri while params keep %2F
--- request
GET /pv/a%2Fb/list
--- error_code: 404
--- error_log
match_uri_view uri=/pv/a/b/list param=a%2Fb



=== TEST 13: set an echo route that returns the request line it received
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/20",
                ngx.HTTP_PUT,
                {
                    uri = "/echo/:id",
                    upstream = {
                        nodes = {["127.0.0.1:1980"] = 1},
                        type = "roundrobin",
                    },
                }
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



=== TEST 14: the upstream receives the original request line with %2F preserved
--- request
GET /echo/a%2Fb
--- response_body
/echo/a%2Fb
