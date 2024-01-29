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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route(return response example:"hello world")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_example": "hello world"
                               }
                           },
                           "uri": "/hello"
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



=== TEST 2: hit route(return response example:"hello world")
--- request
GET /hello
--- response_body chomp
hello world



=== TEST 3: set route(return response schema: string case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_schema": {
                                       "type": "object",
                                       "properties": {
                                           "field1":{
                                               "type":"string",
                                               "example":"hello"
                                           }
                                       }
                                   }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 4: hit route(return response schema: string case)
--- request
GET /hello
--- response_body chomp
{"field1":"hello"}



=== TEST 5: set route(return response schema: integer case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_schema": {
                                       "type": "object",
                                       "properties": {
                                           "field1":{
                                               "type":"integer",
                                               "example":4
                                           }
                                       }
                                   }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 6: hit route(return response schema: integer case)
--- request
GET /hello
--- response_body chomp
{"field1":4}



=== TEST 7: set route(return response schema: number case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_schema": {
                                       "type": "object",
                                       "properties": {
                                           "field1":{
                                               "type":"number",
                                               "example":5.5
                                           }
                                       }
                                   }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 8: hit route(return response schema: number case)
--- request
GET /hello
--- response_body chomp
{"field1":5.5}



=== TEST 9: set route(return response schema: boolean case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_schema": {
                                       "type": "object",
                                       "properties": {
                                           "field1":{
                                               "type":"boolean",
                                               "example":true
                                           }
                                       }
                                   }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 10: hit route(return response schema: boolean case)
--- request
GET /hello
--- response_body chomp
{"field1":true}



=== TEST 11: set route(return response schema: object case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_schema": {
                                       "type": "object",
                                       "properties": {
                                           "field1":{
                                               "type":"object"
                                           }
                                       }
                                   }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 12: hit route(return response schema: object case)
--- request
GET /hello
--- response_body chomp
{"field1":{}}



=== TEST 13: set route(return response header: application/json)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "application/json",
                                   "response_status": 200,
                                   "response_example": "{\"field1\":{}}"
                               }
                           },
                           "uri": "/hello"
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



=== TEST 14: hit route(return response header: application/json)
--- request
GET /hello
--- response_headers
Content-Type: application/json



=== TEST 15: set route(return response example:"remote_addr:127.0.0.1")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_example": "remote_addr:$remote_addr"
                               }
                           },
                           "uri": "/hello"
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



=== TEST 16: hit route(return response example:"remote_addr:127.0.0.1")
--- request
GET /hello
--- response_body chomp
remote_addr:127.0.0.1



=== TEST 17: set route(return response example:"empty_var:")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "delay": 1,
                                   "content_type": "text/plain",
                                   "response_status": 200,
                                   "response_example": "empty_var:$foo"
                               }
                           },
                           "uri": "/hello"
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



=== TEST 18: hit route(return response example:"empty_var:")
--- request
GET /hello
--- response_body chomp
empty_var:



=== TEST 19: set route (return headers)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "response_example": "hello world",
                                   "response_headers": {
                                        "X-Apisix": "is, cool",
                                        "X-Really": "yes"
                                    }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 20: hit route
--- request
GET /hello
--- response_headers
X-Apisix: is, cool
X-Really: yes



=== TEST 21: set route (return headers support built-in variables)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "mocking": {
                                   "response_example": "hello world",
                                   "response_headers": {
                                        "X-route-id": "$route_id"
                                    }
                               }
                           },
                           "uri": "/hello"
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



=== TEST 22: hit route
--- request
GET /hello
--- response_headers
X-route-id: 1
