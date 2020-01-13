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

=== TEST 1: set route(invalid http_status in the abort property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                       "http_status": 100,
                                       "body": "Fault Injection!"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 2: set route(without http_status in the abort property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 3: set route(without abort & delay properties)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/expect object to have at least 1 properties/
--- no_error_log
[error]



=== TEST 4: set route(without duration in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 5: set route(invalid duration with string in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": "test"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
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
--- error_code: 400
--- response_body eval
qr/wrong type: expected number, got string/
--- no_error_log
[error]



=== TEST 6: set route(invalid duration with duoble dot in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 0.1.1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 7: set route(invalid duration with whitespace in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 0. 1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 8: set route(delay 1 seconds)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
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



=== TEST 9: hit route(delay 1 seconds and return hello world)
--- request
GET /hello HTTP/1.1
--- response_body
hello world
--- no_error_log
[error]



=== TEST 10: set route(abort with http status 200 and return "Fault Injection!")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 200,
                                      "body": "Fault Injection!"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
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



=== TEST 11: hit route(abort with http code 200 and return "Fault Injection!")
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 12: set route(abort with http status 405 and return "Fault Injection!")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 405,
                                      "body": "Fault Injection!"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
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



=== TEST 13: hit route(abort with http status 405 and return "Fault Injection!")
--- request
GET /hello HTTP/1.1
--- error_code: 405
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 14: set route(play with redirect plugin)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 200,
                                      "body": "Fault Injection!"
                                   }
                               },
                               "redirect": {
                                   "uri": "/hello/world",
                                   "ret_code": 302
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
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



=== TEST 15: hit route(abort with http status 200 and return "Fault Injection!")
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
Fault Injection!
--- no_error_log
[error]

