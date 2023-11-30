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
            local data = {
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
                {
                    uri = "/apisix/admin/routes/wrong-public-api",
                    data = [[{
                        "plugins": {
                            "public-api": {
                                "uri": "/apisix/plugin/balalbala"
                            }
                        },
                        "uri": "/wrong-public-api"
                    }]]
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.uri, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 4



=== TEST 3: hit route (custom-jwt-sign)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body, jwt = t("/gen_token?key=user-key", ngx.HTTP_GET, "", nil, {apikey = "testkey"})
            if code >= 300 then
                ngx.status = code
            end

            local header = string.sub(jwt, 1, 36)

            if header == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" or
               header == "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9" then
                ngx.say("passed")
                return
            end

            ngx.say("failed")
        }
    }
--- response_body
passed



=== TEST 4: hit route (direct-wolf-rbac-userinfo)
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- error_log
direct-wolf-rbac-userinfo was triggered



=== TEST 5: missing route (non-exist public API)
--- request
GET /apisix/plugin/balalbala
--- error_code: 404



=== TEST 6: hit route (wrong public-api uri)
--- request
GET /wrong-public-api
--- error_code: 404



=== TEST 7: setup route (protect public API)
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    uri = "/apisix/admin/consumers",
                    data = [[{
                        "username": "bob",
                        "plugins": {
                            "key-auth": {
                                "key": "testkey"
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
                            "key-auth": {}
                        },
                        "uri": "/gen_token"
                    }]],
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.uri, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body
201passed
200passed



=== TEST 8: hit route (with key-auth header)
--- request
GET /gen_token?key=user-key
--- more_headers
apikey: testkey



=== TEST 9: hit route (without key-auth header)
--- request
GET /gen_token?key=user-key
--- error_code: 401
