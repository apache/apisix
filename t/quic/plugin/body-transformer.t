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

no_long_string();
no_shuffle();
no_root_location();
run_tests;

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



=== TEST 2: test JSON-to-JSON
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            assert(data.foo == "hello world" and data.bar == 30)
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foo":"{{name .. " world"}}","bar":{{age+10}}}]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/foobar",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local body = [[{"name":"hello","age":20}]]
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }
--- request
GET /t



=== TEST 3: hit
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            assert(data.foo == "hello world" and data.bar == 30)
        }
    }
--- exec
curl -k -v -H "Host: test.com" -H "Content-Type: application/json" -d '{"name":"hello","age":20}' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/foobar 2>&1 | cat
--- response_body eval
qr/HTTP\/3 200/
