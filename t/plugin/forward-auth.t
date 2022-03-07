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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {uri = "http://127.0.0.1:8199"},
                {request_headers = {"test"}},
                {uri = 3233},
                {uri = "http://127.0.0.1:8199", request_headers = "test"}
            }
            local plugin = require("apisix.plugins.forward-auth")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "uri" is required
property "uri" validation failed: wrong type: expected string, got number
property "request_headers" validation failed: wrong type: expected array, got string



=== TEST 2: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/upstreams/u1",
                    data = [[{
                        "nodes": {
                            "127.0.0.1:1984": 1
                        },
                        "type": "roundrobin"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/auth",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": [
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\");
                                        if core.request.header(ctx, \"Authorization\") == \"111\" then
                                            core.response.exit(200);
                                        end
                                    end",
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\");
                                        if core.request.header(ctx, \"Authorization\") == \"222\" then
                                            core.response.set_header(\"X-User-ID\", \"i-am-an-user\");
                                            core.response.exit(200);
                                        end
                                    end",]] .. [[
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\");
                                        if core.request.header(ctx, \"Authorization\") == \"333\" then
                                            core.response.set_header(\"Location\", \"http://example.com/auth\");
                                            core.response.exit(403);
                                        end
                                    end",
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\");
                                        if core.request.header(ctx, \"Authorization\") == \"444\" then
                                            core.response.exit(403, core.request.headers(ctx));
                                        end
                                    end"
                                ]
                            }
                        },
                        "uri": "/auth"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/echo",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": [
                                    "return function (conf, ctx)
                                        local core = require(\"apisix.core\");
                                        core.response.exit(200, core.request.headers(ctx));
                                    end"
                                ]
                            }
                        },
                        "uri": "/echo"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/hello"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/empty"
                    }]],
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 5



=== TEST 3: hit route (test request_headers)
--- request
GET /hello
--- more_headers
Authorization: 111
--- response_body_like eval
qr/\"authorization\":\"111\"/



=== TEST 4: hit route (test upstream_headers)
--- request
GET /hello
--- more_headers
Authorization: 222
--- response_body_like eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 5: hit route (test client_headers)
--- request
GET /hello
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
Location: http://example.com/auth



=== TEST 6: hit route (check APISIX generated headers and ignore client headers)
--- request
GET /hello
--- more_headers
Authorization: 444
X-Forwarded-Host: apisix.apache.org
--- error_code: 403
--- response_body eval
qr/\"x-forwarded-proto\":\"http\"/     and qr/\"x-forwarded-method\":\"GET\"/    and
qr/\"x-forwarded-host\":\"localhost\"/ and qr/\"x-forwarded-uri\":\"\\\/hello\"/ and
qr/\"x-forwarded-for\":\"127.0.0.1\"/
--- response_body_unlike eval
qr/\"x-forwarded-host\":\"apisix.apache.org\"/



=== TEST 7: hit route (not send upstream headers)
--- request
GET /empty
--- more_headers
Authorization: 222
--- response_body_unlike eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 8: hit route (not send client headers)
--- request
GET /empty
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
!Location
