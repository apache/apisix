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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__
=== TEST 1: body transformer plugin with key-auth that fails
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/foobar",
                    "plugins": {
                        "body-transformer": {
                            "request": {
                                "template": "some-template"
                            }
                        },
                        "key-auth": {}
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local opt = {method = "POST", body = "body", headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 401)
            ngx.say(res.reason)
        }
    }
--- response_body
Unauthorized
