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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');
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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: hit route(return response example:"hello world")
--- request
GET /hello
--- error_code: 200
--- response_body chomp
hello world
--- no_error_log
[error]



=== TEST 3: set route(return response schema)
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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: hit route(return response schema)
--- request
GET /hello
--- error_code: 200
--- response_body chomp
{"field1":"hello"}
--- no_error_log
[error]
