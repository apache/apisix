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
    $ENV{VAULT_TOKEN} = "root";
}

use t::APISIX 'no_plan';


repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.wolf-rbac")
            local conf = {
                server = "http://127.0.0.1:12180"
            }

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/\{"appid":"unset","header_prefix":"X-","server":"http:\/\/127\.0\.0\.1:12180"\}/
--- error_log
Using wolf-rbac server with no TLS is a security risk



=== TEST 2: add consumer with username and plugins
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
                            "server": "https://127.0.0.1:1982"
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
--- no_error_log
Using wolf-rbac server with no TLS is a security risk



=== TEST 3: wrong type of string
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
--- response_body
property "appid" validation failed: wrong type: expected string, got number
done



=== TEST 4: setup public API route
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/routes/wolf-login",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/wolf-rbac/login"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/wolf-userinfo",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/wolf-rbac/user_info"
                    }]]
                },
                {
                    url = "/apisix/admin/routes/wolf-change-pwd",
                    data = [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/plugin/wolf-rbac/change_pwd"
                    }]]
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 3



=== TEST 5: add consumer with username and plugins
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



=== TEST 6: enable wolf rbac plugin using admin api
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
--- response_body
passed



=== TEST 7: login failed, appid is missing
--- request
POST /apisix/plugin/wolf-rbac/login
username=admin&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body_like eval
qr/appid is missing/



=== TEST 8: login failed, appid not found
--- request
POST /apisix/plugin/wolf-rbac/login
appid=not-found&username=admin&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body_like eval
qr/appid not found/



=== TEST 9: login failed, username missing
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body
{"message":"request to wolf-server failed!"}
--- grep_error_log eval
qr/ERR_USERNAME_MISSING/
--- grep_error_log_out eval
qr/ERR_USERNAME_MISSING/



=== TEST 10: login failed, password missing
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=admin
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body
{"message":"request to wolf-server failed!"}
--- grep_error_log eval
qr/ERR_PASSWORD_MISSING/
--- grep_error_log_out eval
qr/ERR_PASSWORD_MISSING/



=== TEST 11: login failed, username not found
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=not-found&password=123456
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body
{"message":"request to wolf-server failed!"}
--- grep_error_log eval
qr/ERR_USER_NOT_FOUND/
--- grep_error_log_out eval
qr/ERR_USER_NOT_FOUND/



=== TEST 12: login failed, wrong password
--- request
POST /apisix/plugin/wolf-rbac/login
appid=wolf-rbac-app&username=admin&password=wrong-password
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 200
--- response_body
{"message":"request to wolf-server failed!"}
--- grep_error_log eval
qr/ERR_PASSWORD_ERROR/
--- grep_error_log_out eval
qr/ERR_PASSWORD_ERROR/



=== TEST 13: login successfully
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



=== TEST 14: verify, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing rbac token in request"}



=== TEST 15: verify: invalid rbac token
--- request
GET /hello
--- error_code: 401
--- more_headers
x-rbac-token: invalid-rbac-token
--- response_body
{"message":"invalid rbac token: parse failed"}



=== TEST 16: verify: invalid appid in rbac token
--- request
GET /hello
--- error_code: 401
--- more_headers
x-rbac-token: V1#invalid-appid#rbac-token
--- response_body
{"message":"Invalid appid in rbac token"}
--- error_log
consumer [invalid-appid] not found



=== TEST 17: verify: failed
--- request
GET /hello1
--- error_code: 403
--- more_headers
x-rbac-token: V1#wolf-rbac-app#wolf-rbac-token
--- response_body
{"message":"ERR_ACCESS_DENIED"}
--- grep_error_log eval
qr/ERR_ACCESS_DENIED */
--- grep_error_log_out
ERR_ACCESS_DENIED
ERR_ACCESS_DENIED
ERR_ACCESS_DENIED



=== TEST 18: verify (in argument)
--- request
GET /hello?rbac_token=V1%23wolf-rbac-app%23wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
hello world



=== TEST 19: verify (in header Authorization)
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



=== TEST 20: verify (in header x-rbac-token)
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



=== TEST 21: verify (in cookie)
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



=== TEST 22: get userinfo failed, missing token
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- response_body
{"message":"Missing rbac token in request"}



=== TEST 23: get userinfo failed, invalid rbac token
--- request
GET /apisix/plugin/wolf-rbac/user_info
--- error_code: 401
--- more_headers
x-rbac-token: invalid-rbac-token
--- response_body
{"message":"invalid rbac token: parse failed"}



=== TEST 24: get userinfo
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



=== TEST 25: change password failed, old password incorrect
--- request
PUT /apisix/plugin/wolf-rbac/change_pwd
{"oldPassword": "error", "newPassword": "abcdef"}
--- more_headers
Content-Type: application/json
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- error_code: 200
--- response_body
{"message":"request to wolf-server failed!"}
--- grep_error_log eval
qr/ERR_OLD_PASSWORD_INCORRECT/
--- grep_error_log_out eval
qr/ERR_OLD_PASSWORD_INCORRECT/



=== TEST 26: change password
--- request
PUT /apisix/plugin/wolf-rbac/change_pwd
{"oldPassword":"123456", "newPassword": "abcdef"}
--- more_headers
Content-Type: application/json
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- error_code: 200
--- response_body_like eval
qr/success to change password/



=== TEST 27: custom headers in request headers
--- request
GET /wolf/rbac/custom/headers?rbac_token=V1%23wolf-rbac-app%23wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
id:100,username:admin,nickname:administrator



=== TEST 28: change password by post raw args
--- request
PUT /apisix/plugin/wolf-rbac/change_pwd
oldPassword=123456&newPassword=abcdef
--- more_headers
Cookie: x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token
--- error_code: 200
--- response_body_like eval
qr/success to change password/



=== TEST 29: change password by post raw args, greater than 100 args is ok
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin")

        local headers = {
            ["Cookie"] = "x-rbac-token=V1#wolf-rbac-app#wolf-rbac-token"
        }
        local tbl = {}
        for i=1, 100 do
            tbl[i] = "test"..tostring(i).."=test&"
        end
        tbl[101] = "oldPassword=123456&newPassword=abcdef"
        local code, _, real_body = t.test('/apisix/plugin/wolf-rbac/change_pwd',
            ngx.HTTP_PUT,
            table.concat(tbl, ""),
            nil,
            headers
        )
        ngx.status = 200
        ngx.say(real_body)
    }
}
--- response_body_like eval
qr/success to change password/



=== TEST 30: verify: failed, server internal error
--- request
GET /hello/500
--- error_code: 500
--- more_headers
x-rbac-token: V1#wolf-rbac-app#wolf-rbac-token
--- response_body
{"message":"request to wolf-server failed, status:500"}
--- grep_error_log eval
qr/request to wolf-server failed, status:500 */
--- grep_error_log_out
request to wolf-server failed, status:500
request to wolf-server failed, status:500



=== TEST 31: verify: failed, token is expired
--- request
GET /hello/401
--- error_code: 401
--- more_headers
x-rbac-token: V1#wolf-rbac-app#wolf-rbac-token
--- response_body
{"message":"ERR_TOKEN_INVALID"}
--- grep_error_log eval
qr/ERR_TOKEN_INVALID */
--- grep_error_log_out
ERR_TOKEN_INVALID
ERR_TOKEN_INVALID
ERR_TOKEN_INVALID



=== TEST 32: set hmac-auth conf: appid uses secret ref
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
             -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "root"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "wolf_rbac_unit_test",
                    "plugins": {
                        "wolf-rbac": {
                            "appid": "$secret://vault/test1/wolf_rbac_unit_test/appid",
                            "server": "http://127.0.0.1:1982"
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



=== TEST 33: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/wolf_rbac_unit_test appid=wolf-rbac-app
--- response_body
Success! Data written to: kv/apisix/wolf_rbac_unit_test



=== TEST 34: login successfully
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



=== TEST 35: set hmac-auth conf with the token in an env var: appid uses secret ref
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
             -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "$ENV://VAULT_TOKEN"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "wolf_rbac_unit_test",
                    "plugins": {
                        "wolf-rbac": {
                            "appid": "$secret://vault/test1/wolf_rbac_unit_test/appid",
                            "server": "http://127.0.0.1:1982"
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



=== TEST 36: login successfully
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



=== TEST 37: add consumer with echo plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "wolf_rbac_with_other_plugins",
                    "plugins": {
                        "wolf-rbac": {
                            "appid": "wolf-rbac-app",
                            "server": "http://127.0.0.1:1982"
                        },
                        "echo": {
                            "body": "consumer merge echo plugins\n"
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
--- no_error_log
[error]



=== TEST 38: verify echo plugin in consumer
--- request
GET /hello
--- more_headers
Authorization: V1#wolf-rbac-app#wolf-rbac-token
--- response_headers
X-UserId: 100
X-Username: admin
X-Nickname: administrator
--- response_body
consumer merge echo plugins
--- no_error_log
[error]
