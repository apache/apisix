use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: create a credential for invalid consumer: consumer not found error
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_a',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body
{"error_msg":"consumer not found"}



=== TEST 2: add a consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack",
                     "desc": "new consumer",
                     "plugins": {
                         "basic-auth": {
                             "username": "the-user",
                             "password": "the-password"
                         }
                     }
                }]],
                [[{
                    "key": "/apisix/consumers/jack",
                    "value":
                    {
                        "username":"jack",
                        "desc": "new consumer",
                        "plugins": {
                            "basic-auth": {
                                "username": "the-user",
                                "password": "the-password"
                            }
                        }
                    }
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



=== TEST 3: add a credentials with basic-auth for the consumer jack, should success
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_a',
                ngx.HTTP_PUT,
                [[{
                     "desc": "basic-auth for jack",
                     "plugins": {
                         "basic-auth": {
                             "username": "the-user",
                             "password": "the-password"
                         }
                     }
                }]],
                [[{
                    "value":{
                        "desc":"basic-auth for jack",
                        "id":"credential_a",
                        "plugins":{"basic-auth":{"username":"the-user","password":"the-password"}}
                    },
                    "key":"/apisix/consumers/jack/credentials/credential_a"
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



=== TEST 4: add a credential with key-auth for the consumer jack, should success
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_b',
                ngx.HTTP_PUT,
                [[{
                     "desc": "key-auth for jack",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
                }]],
                [[{
                    "value":{
                        "desc":"key-auth for jack",
                        "id":"credential_b",
                        "plugins":{"key-auth":{"key":"the-key"}}
                    },
                    "key":"/apisix/consumers/jack/credentials/credential_b"
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



=== TEST 5: add a credential with a plugin which is not a auth plugin, should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_b',
                ngx.HTTP_PUT,
                [[{
                     "desc": "limit-conn for jack",
                     "plugins": {
                         "limit-conn": {
                            "conn": 1,
                            "burst": 0,
                            "default_conn_delay": 0.1,
                            "rejected_code": 503,
                            "key_type": "var",
                            "key": "http_a"
                         }
                     }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"only supports auth type plugins in consumer credential"}



=== TEST 6: list consumers: should not contain credential
--- config
    location /t {
        content_by_lua_block {
	        local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body, res = t('/apisix/admin/consumers', ngx.HTTP_GET)

            ngx.status = code
	        res = json.decode(res)
	        assert(res.total == 1)
	        assert(res.list[1].key == "/apisix/consumers/jack")
        }
    }
--- request
GET /t
--- response_body



=== TEST 7: list credentials: should contain credential_a and credential_b
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body, res = t('/apisix/admin/consumers/jack/credentials', ngx.HTTP_GET)

            ngx.status = code
            res = json.decode(res)
            assert(res.total == 2)
            assert(res.list[1].key == "/apisix/consumers/jack/credentials/credential_a")
            assert(res.list[2].key == "/apisix/consumers/jack/credentials/credential_b")
        }
    }
--- request
GET /t
--- response_body


=== TEST 8: get a credential
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_b',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "key": "/apisix/consumers/jack/credentials/credential_b",
                    "value": {
                        "desc": "key-auth for jack",
                         "plugins": {"key-auth": {"key": "the-key"}
                     }}
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



=== TEST 9: update credential: should ok
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_b',
                ngx.HTTP_PUT,
                [[{
                     "desc": "new description",
                     "plugins": {
                         "key-auth": {
                             "key": "new-key"
                         }
                     }
                }]],
                [[{
                    "key": "/apisix/consumers/jack/credentials/credential_b",
                     "value": {
                         "desc": "new description",
                         "plugins": {
                             "key-auth": {
                                 "key": "new-key"
                             }
                         }
                     }
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



=== TEST 10: delete credential
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/credential_a', ngx.HTTP_DELETE)

            assert(code == 200)
            ngx.status = code

            code, body, res = t('/apisix/admin/consumers/jack/credentials', ngx.HTTP_GET)
            res = json.decode(res)
            assert(res.total == 1)
            assert(res.list[1].key == "/apisix/consumers/jack/credentials/credential_b")
        }
    }
--- request
GET /t
--- response_body



=== TEST 11: create a credential has more than one plugin: should not ok
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials/xxx-yyy-zzz',
                ngx.HTTP_PUT,
                [[{
                     "plugins": {
                         "key-auth": {"key": "the-key"},
                         "basic-auth": {"username": "the-user", "password": "the-password"}
                     }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"plugins\" validation failed: expect object to have at most 1 properties"}



=== TEST 12: delete consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_DELETE
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 13: list credentials: should get 404 because the consumer is deleted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials', ngx.HTTP_GET)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body
{"message":"Key not found"}



=== TEST 14: add a consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack"
                }]]
            )

            if ngx.status >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 15: add a credential with key-auth for the consumer jack (id in the payload but not in uri), should success
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials',
                ngx.HTTP_PUT,
                [[{
                     "id": "d79a5aa3",
                     "desc": "key-auth for jack",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
                }]],
                [[{
                    "value":{
                        "desc":"key-auth for jack",
                        "id":"d79a5aa3",
                        "plugins":{"key-auth":{"key":"the-key"}}
                    },
                    "key":"/apisix/consumers/jack/credentials/d79a5aa3"
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



=== TEST 16: add a credential with key-auth for the consumer jack but missing id in uri and payload, should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack/credentials',
                ngx.HTTP_PUT,
                [[{
                     "desc": "key-auth for jack",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing credential id"}
