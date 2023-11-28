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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}


repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
wasm:
    plugins:
        - name: wasm-forward-auth
          priority: 7997
          file: t/wasm/forward-auth.go.wasm
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);
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
                                            core.response.set_header(\"X-User-ID\", \"i-am-an-user\");
                                            core.response.exit(401);
                                        end
                                    end",
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\");
                                        if core.request.header(ctx, \"Authorization\") == \"444\" then
                                            local auth_headers = {
                                                'X-Forwarded-Proto',
                                                'X-Forwarded-Method',
                                                'X-Forwarded-Host',
                                                'X-Forwarded-Uri',
                                                'X-Forwarded-For',
                                            }
                                            for _, k in ipairs(auth_headers) do
                                                core.log.warn('get header ', string.lower(k), ': ', core.request.header(ctx, k))
                                            end
                                            core.response.exit(403);
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
                            "wasm-forward-auth": {
                                "conf": "{
                                    \"uri\": \"http://127.0.0.1:1984/auth\",
                                    \"request_headers\": [\"Authorization\"],
                                    \"client_headers\": [\"X-User-ID\"],
                                    \"upstream_headers\": [\"X-User-ID\"]
                                }"
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
                            "wasm-forward-auth": {
                                "conf": "{
                                    \"uri\": \"http://127.0.0.1:1984/auth\",
                                    \"request_headers\": [\"Authorization\"]
                                }"
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
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 5



=== TEST 2: hit route (test request_headers)
--- request
GET /hello
--- more_headers
Authorization: 111
--- response_body_like eval
qr/\"authorization\":\"111\"/



=== TEST 3: hit route (test upstream_headers)
--- request
GET /hello
--- more_headers
Authorization: 222
--- response_body_like eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 4: hit route (test client_headers)
--- request
GET /hello
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
x-user-id: i-am-an-user



=== TEST 5: hit route (check APISIX generated headers and ignore client headers)
--- request
GET /hello
--- more_headers
Authorization: 444
X-Forwarded-Host: apisix.apache.org
--- error_code: 403
--- grep_error_log eval
qr/get header \S+: \S+/
--- grep_error_log_out
get header x-forwarded-proto: http,
get header x-forwarded-method: GET,
get header x-forwarded-host: localhost,
get header x-forwarded-uri: /hello,
get header x-forwarded-for: 127.0.0.1,



=== TEST 6: hit route (not send upstream headers)
--- request
GET /empty
--- more_headers
Authorization: 222
--- response_body_unlike eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 7: hit route (not send client headers)
--- request
GET /empty
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
!x-user-id
