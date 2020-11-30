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
no_shuffle();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.wolf-rbac")
            local conf = {

            }

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/\{"appid":"unset","header_prefix":"X-","server":"http:\/\/127\.0\.0\.1:10080"\}/
--- no_error_log
[error]



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.wolf-rbac")
            local ok, err = plugin.check_schema({appid = 123})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "appid" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "wolf_rbac_unit_test",
                    "plugins": {
                        "wolf-rbac": {
                            "appid": "wolf-rbac-app",
                            "server": "http://127.0.0.1:1982"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "wolf_rbac_unit_test",
                            "plugins": {
                                "wolf-rbac": {
                                    "appid": "wolf-rbac-app",
                                    "server": "http://127.0.0.1:1982"
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 4: enable wolf rbac plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "wolf-rbac": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello*","/wolf/rbac/*"]
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



=== TEST 5: login failed, appid is missing
--- request
POST /apisix/plugin/wolf-rbac/login
username=admin&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body_like eval
qr/appid is missing/
--- no_error_log
[error]



=== TEST 6: login failed, appid not found
--- request
POST /apisix/plugin/wolf-rbac/login
appid=not-found&username=admin&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body_like eval
qr/appid \[not-found\] not found/
--- no_error_log
[error]



=== TEST 7: login failed, username missing
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body_like eval
qr/ERR_USERNAME_MISSING/



=== TEST 8: login failed, password missing
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=admin
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body_like eval
qr/ERR_PASSWORD_MISSING/



=== TEST 9: login failed, username not found
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=not-found&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body_like eval
qr/ERR_USER_NOT_FOUND/



=== TEST 10: login failed, wrong password
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=admin&password=wrong-password
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body_like eval
qr/ERR_PASSWORD_ERROR/



=== TEST 11: login successfully
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/plugin/wolf-rbac/login',
                ngx.HTTP_POST,
                [[
                {"appid": "wolf-rbac-app", "username": "admin","password": "123456"}
                ]],
                [[
                {"rbac_token":"V1#wolf-rbac-app#wolf-rbac-token","user_info":{"nickname":"administrator","username":"admin","id":"100"}}
                ]],
                {["Content-Type"] = "application/json"}
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 12: verify, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing rbac token in request"}
--- no_error_log
[error]



=== TEST 13: verify: invalid rbac token
--- request
GET /hello
--- error_code: 401
--- more_headers
x-rbac-token: invalid-rbac-token
--- response_body
{"message":"invalid rbac token: parse failed"}
--- no_error_log
[error]



=== TEST 14: verify: invalid appid in rbac token
--- request
GET /hello
--- error_code: 401
--- more_headers
x-rbac-token: V1#invalid-appid#rbac-token
--- response_body
{"message":"Invalid appid in rbac token"}



=== TEST 15: verify: failed
--- request
GET /hello1
--- error_code: 401
--- more_headers
x-rbac-token: V1#wolf-rbac-app#wolf-rbac-token
--- response_body
{"message":"no permission to access"}



=== TEST 16: verify (in argument)
--- request
GET /hello?rbac_token=V1%23wolf-rbac-app%23wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
hello world
--- no_error_log
[error]



=== TEST 17: verify (in header Authorization)
--- request
GET /hello
--- more_headers
Authorization: V1#wolf-rbac-app#wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
hello world
--- no_error_log
[error]



=== TEST 18: verify (in header x-rbac-token)
--- request
GET /hello
--- more_headers
x-rbac-token: V1#wolf-rbac-app#wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
hello world
--- no_error_log
[error]



=== TEST 19: verify (in cookie)
--- request
GET /hello
--- more_headers
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
hello world
--- no_error_log
[error]



=== TEST 20: get userinfo failed, missing token
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- response_body
{"message":"Missing rbac token in request"}
--- no_error_log
[error]



=== TEST 21: get userinfo failed, invalid rbac token
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- more_headers
x-rbac-token: invalid-rbac-token
--- response_body
{"message":"invalid rbac token: parse failed"}
--- no_error_log
[error]



=== TEST 22: get userinfo
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/plugin/wolf-rbac/user_info',
                ngx.HTTP_GET,
                nil,
                [[
{"user_info":{"username":"admin","id":"100","nickname":"administrator"}}
                ]],
                {Cookie = "x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token"}
                )
            ngx.status = code
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 23: change password failed, old password incorrect
--- request
PUT /apisix/plugin/wolf-rbac/change_pwd
{"oldPassword": "error", "newPassword": "abcdef"}
--- more_headers
Content-Type: application/json
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- error_code: 200
--- response_body_like eval
qr/ERR_OLD_PASSWORD_INCORRECT/



=== TEST 24: change password
--- request
PUT /apisix/plugin/wolf-rbac/change_pwd
{"oldPassword":"123456", "newPassword": "abcdef"}
--- more_headers
Content-Type: application/json
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- error_code: 200
--- response_body_like eval
qr/success to change password/



=== TEST 25: custom headers in request headers
--- request
GET /wolf/rbac/custom/headers?rbac_token=V1%23wolf-rbac-app%23wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
id:100,username:admin,nickname:administrator
--- no_error_log
[error]
