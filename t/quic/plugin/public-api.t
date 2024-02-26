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
run_tests();

__DATA__

=== TEST 1:  create ssl for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



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
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.uri, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- request
GET /t
--- response_body eval
"201passed\n" x 2



=== TEST 3: hit route (direct-wolf-rbac-userinfo)
--- exec
curl -k -v -H "Host: test.com" -H "content-length: 0" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/apisix/plugin/wolf-rbac/user_info 2>&1 | cat
--- response_body eval
qr/401/
--- error_log
direct-wolf-rbac-userinfo was triggered
