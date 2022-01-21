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
                {uri = "/apisix/plugin/jwt/sign"},
                {uri = 3233}
            }
            local plugin = require("apisix.plugins.public-api")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "uri" validation failed: wrong type: expected string, got number



=== TEST 2: set route
--- config
    location /t {
        content_by_lua_block {
            local datas = {
                {
                    uri = "/apisix/admin/consumers",
                    data = [[{
                        "username": "alice",
                        "plugins": {
                            "jwt-auth": {
                                "key": "user-key",
                                "algorithm": "HS256"
                            }
                        }
                    }]]
                },
                {
                    uri = "/apisix/admin/routes/custom-jwt-sign",
                    data = [[{
                        "plugins": {
                            "public-api": {
                                "uri": "/apisix/plugin/jwt/sign"
                            },
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": ["return function(conf, ctx) require(\"apisix.core\").log.warn(\"custom-jwt-sign was triggered\"); end"]
                            }
                        },
                        "uri": "/gen_token"
                    }]],
                },
                {
                    uri = "/apisix/admin/routes/direct-wolf-rbac-userinfo",
                    data = [[{
                        "plugins": {
                            "public-api": {},
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": ["return function(conf, ctx) require(\"apisix.core\").log.warn(\"direct-wolf-rbac-userinfo was triggered\"); end"]
                            }
                        },
                        "uri": "/apisix/plugin/wolf-rbac/user_info"
                    }]],
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(datas) do
                local code, body = t(data.uri, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 3



=== TEST 3: hit route (custom-jwt-sign)
--- request
GET /gen_token?key=user-key
--- error_log
custom-jwt-sign was triggered
--- response_body eval
qr/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9/ or
qr/eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9/



=== TEST 4: hit route (direct-wolf-rbac-userinfo)
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- error_log
direct-wolf-rbac-userinfo was triggered



=== TEST 5: missing route
--- request
GET /apisix/plugin/balalbala
--- error_code: 404
