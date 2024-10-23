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
BEGIN {
    $ENV{VAULT_TOKEN} = "root";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
        if (!$block->response_body) {
            $block->set_value("response_body", "passed\n");
        }
    }
});

run_tests;

__DATA__

=== TEST 1: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 2: enable jwt auth plugin using admin api with default config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {},
                        "serverless-post-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function(conf, ctx)
                                if ctx.jwt_obj then
                                    ngx.status = 200
                                    ngx.say(\"JWT found in ctx. Payload key: \" .. ctx.jwt_obj.payload.key)
                                    return ngx.exit(200)
                                else
                                    ngx.status = 500
                                    ngx.say(\"JWT not found in ctx.\")
                                    return ngx.exit(500)
                                end
                                end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/jwt-auth-no-ctx"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 3: enable jwt auth plugin using admin api with custom parameter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "store_in_ctx": true
                        },
                        "serverless-post-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function(conf, ctx)
                                if ctx.jwt_obj then
                                    ngx.status = 200
                                    ngx.say(\"JWT found in ctx. Payload key: \" .. ctx.jwt_obj.payload.key)
                                    return ngx.exit(200)
                                else
                                    ngx.status = 500
                                    ngx.say(\"JWT not found in ctx.\")
                                    return ngx.exit(500)
                                end
                                end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/jwt-auth-ctx"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }



=== TEST 4: verify (header with bearer)
--- request
GET /jwt-auth-no-ctx
--- more_headers
Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsIm5iZiI6MTcyNzI3NDk4M30.N6ebc4U5ms976pwKZ_iQ88w_uJKqUVNtTYZ_nXhRpWo
--- error_code: 500
--- response_body
JWT not found in ctx.



=== TEST 5: verify (header with bearer)
--- request
GET /jwt-auth-ctx
--- more_headers
Authorization: bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsIm5iZiI6MTcyNzI3NDk4M30.N6ebc4U5ms976pwKZ_iQ88w_uJKqUVNtTYZ_nXhRpWo
--- error_code: 200
--- response_body
JWT found in ctx. Payload key: user-key
