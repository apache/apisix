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
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "rewrite",
                                functions =  {
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "111" then
                                            core.response.exit(200);
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
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- request
GET /t
--- response_body eval
"passed\n" x 4



=== TEST 3: hit route (test request_headers)
--- exec
curl -k -v -H "Host: test.com" -H "content-length: 0" -H "Authorization: 111" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/hello 2>&1 | cat
--- response_body_like eval
qr/\"authorization\":\"111\"/
