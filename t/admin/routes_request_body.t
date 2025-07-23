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

log_level("info");
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

=== TEST 1: set route in request body vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "vars": [
                        [
                            ["post_arg.model","==", "deepseek"]
                        ]
                    ],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.org:80": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "vars": [
                        [
                            ["post_arg.model","==","openai"]
                        ]
                    ],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: send request with model == deepseek
--- request
POST /hello
{ "model":"deepseek", "messages": [ { "role": "system", "content": "You are a mathematician" }] }
--- more_headers
Content-Type: application/json
--- error_code: 404



=== TEST 3: send request with model == openai and content-type == application/json
--- request
POST /hello
{ "model":"openai", "messages": [ { "role": "system", "content": "You are a mathematician" }] }
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 4: send request with model == openai and content-type == application/x-www-form-urlencoded
--- request
POST /hello
model=openai&messages[0][role]=system&messages[0][content]=You%20are%20a%20mathematician
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200



=== TEST 5: multipart/form-data with model=openai
--- request
POST /hello
--testboundary
Content-Disposition: form-data; name="model"

openai
--testboundary--
--- more_headers
Content-Type: multipart/form-data; boundary=testboundary
--- error_code: 200



=== TEST 6: no match without content type
--- request
POST /hello
--testboundary
Content-Disposition: form-data; name="model"

openai
--testboundary--
--- error_code: 404
--- error_log
unsupported content-type in header:



=== TEST 7: use array in request body vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "vars": [
                        [
                            ["post_arg.messages[*].content[*].type","has","image_url"]
                        ]
                    ],
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



=== TEST 8: send request with type not image_url
--- request
POST /hello
{ "model":"deepseek", "messages": [ { "role": "system", "content": [{"text":"You are a mathematician","type":"text"}] }] }
--- more_headers
Content-Type: application/json
--- error_code: 404



=== TEST 9: send request with type has image_url
--- request
POST /hello
{ "model":"deepseek", "messages": [ { "role": "system", "content": [{"text":"You are a mathematician","type":"text"},{"text":"You are a mathematician","type":"image_url"}] }] }
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 10: use invalid jsonpath input
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "vars": [
                        [
                            ["post_arg.messages[.content[*].type","has","image_url"]
                        ]
                    ],
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
--- response_body eval
qr/.*failed to validate the 'vars' expression: invalid expression.*/
--- error_code: 400



=== TEST 11: use non array in request body vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "vars": [
                        [
                            ["post_arg.model.name","==","deepseek"]
                        ]
                    ],
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



=== TEST 12: send request
--- request
POST /hello
{ "model":{"name": "deepseek"}, "messages": [ { "role": "system", "content": [{"text":"You are a mathematician","type":"text"},{"text":"You are a mathematician","type":"image_url"}] }] }
--- more_headers
Content-Type: application/json
--- error_code: 200
