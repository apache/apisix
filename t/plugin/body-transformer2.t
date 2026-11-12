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

=== TEST 1: body transformer with decoded body (keyword: context)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

            local req_template = ngx.encode_base64[[
                {%
                    local core = require 'apisix.core'
                    local cjson = require 'cjson'
                    context.name = "bar"
                    context.address = nil
                    context.age = context.age + 1
                    local body = core.json.encode(context)
                %}{* body *}
            ]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/echo",
                    "plugins": {
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]], req_template)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: verify the transformed body
--- request
POST /echo
{"name": "foo", "address":"LA", "age": 18}
-- response_body
{"name": "bar", "age": 19}



=== TEST 3: body transformer plugin with key-auth that fails
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



=== TEST 4: body transformer with input_format json
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo_prim",
                    "plugins": {
                        "body-transformer": {
                            "request": {
                                "input_format": "json",
                                "template": "hello"
                            }
                        }
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: reject JSON number primitive with 400
--- request
POST /echo_prim
123
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"request body decode: expected JSON object or array"}
--- no_error_log
[error]
attempt to index local 'out'



=== TEST 6: reject JSON string primitive with 400
--- request
POST /echo_prim
"hello"
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"request body decode: expected JSON object or array"}
--- no_error_log
[error]
attempt to index local 'out'



=== TEST 7: reject JSON boolean primitive with 400
--- request
POST /echo_prim
true
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"request body decode: expected JSON object or array"}
--- no_error_log
[error]
attempt to index local 'out'



=== TEST 8: reject JSON null primitive with 400
--- request
POST /echo_prim
null
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"request body decode: expected JSON object or array"}
--- no_error_log
[error]
attempt to index local 'out'



=== TEST 9: accept valid JSON array
--- request
POST /echo_prim
[1, 2, 3]
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_body
hello
--- no_error_log
[error]
