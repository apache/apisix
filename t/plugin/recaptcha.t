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

log_level('debug');
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
                recaptcha_secret_key = "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe",
                apis = {
                    {
                        path = "/login",
                        methods = { "POST" },
                        param_from = "header",
                        param_name = "recaptcha"
                    }
                },
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

== TEST 2: invalid recaptcha_secret_key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.recaptcha")
            local ok, err = plugin.check_schema({
                recaptcha_secret_key = nil,
                apis = {
                    {
                        path = "/login",
                        methods = { "POST" },
                        param_from = "header",
                        param_name = "captcha"
                    }
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
property "recaptcha_secret_key" is required
done
--- no_error_log
[error]



=== TEST 2: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "recaptcha": {
                              "recaptcha_secret_key": "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe",
                              "apis": [
                                  {
                                      "path": "/login",
                                      "methods": [
                                          "POST"
                                      ],
                                      "param_from": "header",
                                      "param_name": "captcha"
                                  },
                                  {
                                      "path": "/users/*/active",
                                      "methods": [
                                          "POST"
                                      ],
                                      "param_from": "query",
                                      "param_name": "captcha"
                                  }
                              ],
                              "response": {
                                "content_type": "application/json; charset=utf-8",
                                "status_code": 400,
                                "body": "{\"message\":\"invalid captcha\"}\n"
                              }
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: add fault-injection plugin for mocking upstream api response
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 200,
                                        "body": "{\"message\": \"login success\"}\n"
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
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 200,
                                        "body": "{\"message\": \"active user success\"}\n"
                                    }
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/users/*/active"
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
                   ngx.say(body)
               end


               code, body = t('/apisix/admin/routes/3',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 200,
                                        "body": "{\"message\": \"welcome\"}\n"
                                    }
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/welcome"
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



=== TEST 4: request is terminated by recaptcha plugin due to api /login
--- request
POST /login
--- error_code: 400
--- response_headers
Content-Type: application/json; charset=utf-8
--- response_body
{"message":"invalid captcha"}
--- no_error_log
[error]



=== TEST 5: request is terminated by recaptcha plugin due to api /users/*/active
--- request
POST /users/1/active
--- error_code: 400
--- response_headers
Content-Type: application/json; charset=utf-8
--- response_body
{"message":"invalid captcha"}
--- no_error_log
[error]



=== TEST 6: request pass cases
--- request
GET /login
--- error_code: 200
--- response_body
{"message": "login success"}
--- no_error_log
[error]

--- request
POST /login_other
--- error_code: 404
--- no_error_log
[error]

--- request
GET /users/*/active
--- error_code: 200
--- response_body
{"message": "active user success"}
--- no_error_log
[error]

--- request
POST /users/*/deactivate
--- error_code: 404
--- no_error_log
[error]

--- request
GET /welcome
--- error_code: 200
--- response_body
{"message": "welcome"}
--- no_error_log
[error]



=== TEST 7: recaptcha valid
--- request
POST /login
--- more_headers
captcha: test
--- response_body
{"message": "login success"}
--- no_error_log
[error]



=== TEST 8: recaptcha valid
--- request
POST /users/1/active?captcha=test
--- response_body
{"message": "active user success"}
--- no_error_log
[error]
