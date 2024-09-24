use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__


=== TEST 1: enable basic-auth on the route /hello
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
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
--- response_body
passed



=== TEST 2: create a consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack"
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



=== TEST 3: create a credential with basic-auth plugin enabled for the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "basic-auth": {"username": "foo", "password": "bar"}
                     }
                }]],
                [[{
                    "value":{
                        "id":"34010989-ce4e-4d61-9493-b54cca8edb31",
                        "plugins":{
                            "basic-auth":{"username":"foo","password":"bar"}
                        }
                    },
                    "key":"/apisix/consumers/jack/credentials/34010989-ce4e-4d61-9493-b54cca8edb31"
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



=== TEST 4: access with invalid basic-auth (invalid password)
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}



=== TEST 5: access with valid basic-auth
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
