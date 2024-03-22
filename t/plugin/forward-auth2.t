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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup route with plugin
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
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "rewrite",
                                functions =  {
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        local token = "token-headers-test";
                                        if core.request.header(ctx, "Authorization") == token then
                                            if core.request.get_method() == "POST" then
                                                if core.request.header(ctx, "Content-Length") or
                                                core.request.header(ctx, "Transfer-Encoding") or
                                                core.request.header(ctx, "Content-Encoding") then
                                                    core.response.exit(200)
                                                else
                                                    core.response.exit(403)
                                                end
                                            else
                                                if core.request.header(ctx, "Content-Length") or
                                                core.request.header(ctx, "Transfer-Encoding") or
                                                core.request.header(ctx, "Content-Encoding") then
                                                    core.response.exit(403)
                                                else
                                                    core.response.exit(200)
                                                end
                                            end
                                        end
                                    end]]
                                }
                            }
                        },
                        uri = "/auth"
                    },
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
                                "request_method": "POST"
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/verify-auth-post"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "GET"
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/verify-auth-get"
                    }]],
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 5



=== TEST 2: verify auth server forward headers for request_method=GET
--- request
GET /verify-auth-get
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 3: verify auth server forward headers for request_method=POST for GET upstream
--- request
GET /verify-auth-post
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 4: verify auth server forward headers for request_method=POST
--- request
POST /verify-auth-post
{"authorization": "token-headers-test"}
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 5: verify auth server forward headers for request_method=GET for POST upstream
--- request
POST /verify-auth-get
{"authorization": "token-headers-test"}
--- more_headers
Authorization: token-headers-test
--- error_code: 200
