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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;


__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.recaptcha")
            local ok, err = plugin.check_schema({
                # https://developers.google.com/recaptcha/docs/faq#id-like-to-run-automated-tests-with-recaptcha
                secret_key = "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe", # Google automated-tests secret key
                parameter_source = "header",
                parameter_name = "captcha",
                response = {
                    content_type = "application/json; charset=utf-8",
                    status_code = 400,
                    body = "{\"message\":\"invalid captcha\"}\n"
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



== TEST 2: invalid secret_key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.recaptcha")
            local ok, err = plugin.check_schema({
                secret_key = nil,
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "secret_key" is required
done
--- no_error_log
[error]



=== TEST 2: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                       "plugins": {
                          "recaptcha": {
                              "secret_key": "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe",
                              "parameter_source": "header",
                              "parameter_name": "captcha",
                              "response": {
                                "content_type": "application/json; charset=utf-8",
                                "status_code": 400,
                                "body": "{\"message\":\"invalid captcha\"}\n"
                              }
                          }
                       },
                       "upstream": {
                           "nodes": {
                               "127.0.0.1:1980": 1
                           },
                           "type": "roundrobin"
                       },
                       "uri": "/index"
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
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: add plugin on routes
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                              "recaptcha": {
                                  "secret_key": "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe",
                                  "parameter_source": "header",
                                  "parameter_name": "captcha",
                                  "response": {
                                    "content_type": "application/json; charset=utf-8",
                                    "status_code": 400,
                                    "body": "{\"message\":\"invalid captcha\"}\n"
                                  }
                              }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/login"
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
                   ngx.say(body)
               end

               code, body = t('/apisix/admin/routes/2',
                   ngx.HTTP_PUT,
                   [=[{
                          "plugins": {
                             "recaptcha": {
                                 "secret_key": "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe",
                                 "parameter_source": "query",
                                 "parameter_name": "captcha",
                                 "response": {
                                   "content_type": "application/json; charset=utf-8",
                                   "status_code": 400,
                                   "body": "{\"message\":\"invalid captcha\"}\n"
                                 }
                             }
                          },
                          "upstream": {
                              "nodes": {
                                  "127.0.0.1:1980": 1
                              },
                              "type": "roundrobin"
                          },
                          "uri": "/active"
                  }]=]
                  )
               if code >= 300 then
                   ngx.status = code
               end

               ngx.say(body)
           }
       }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: request is terminated by recaptcha plugin
--- request
POST /login
--- error_code: 400
--- response_headers
Content-Type: application/json; charset=utf-8
--- response_body
{"message":"invalid captcha"}
--- no_error_log
[error]
--- request
POST /active
--- error_code: 400
--- response_headers
Content-Type: application/json; charset=utf-8
--- response_body
{"message":"invalid captcha"}
--- no_error_log
[error]



=== TEST 5: recaptcha valid
--- request
POST /login
--- more_headers
captcha: test
--- error_code: 404
--- no_error_log
[error]



=== TEST 6: recaptcha valid
--- request
POST /active?captcha=test
--- error_code: 404
--- no_error_log
[error]
