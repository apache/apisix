use t::APISIX 'no_plan';

no_root_location();

run_tests;

__DATA__

=== TEST 1: set ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("conf/cert/apisix.crt")
            local ssl_key =  t.read_file("conf/cert/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "sni": "test.com"
                        },
                        "key": "/apisix/ssl/1"
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



=== TEST 2: get ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/ssl/1',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "value": {
                            "sni": "test.com"
                        },
                        "key": "/apisix/ssl/1"
                    },
                    "action": "get"
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



=== TEST 3: delete ssl(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/ssl/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: delete ssl(id: 99999999999999)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/ssl/99999999999999',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404
--- no_error_log
[error]



=== TEST 5: push ssl + delete
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("conf/cert/apisix.crt")
            local ssl_key =  t.read_file("conf/cert/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "foo.com"}

            local code, message, res = t.test('/apisix/admin/ssl',
                ngx.HTTP_POST,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "sni": "foo.com"
                        }
                    },
                    "action": "create"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/ssl/" + 1)
            code, message = t.test('/apisix/admin/ssl/' .. id,
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
            )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 6: missing certificate information
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("conf/cert/apisix.crt")
            local ssl_key =  t.read_file("conf/cert/apisix.key")
            local data = {sni = "foo.com"}

            local code, body = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "sni": "foo.com"
                        },
                        "key": "/apisix/ssl/1"
                    },
                    "action": "set"
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
{"error_msg":"invalid configuration: invalid \"required\" in docuement at pointer \"#\""}
--- no_error_log
[error]



=== TEST 7: wildcard host name
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("conf/cert/apisix.crt")
            local ssl_key =  t.read_file("conf/cert/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "*.foo.com"}

            local code, body = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "sni": "*.foo.com"
                        },
                        "key": "/apisix/ssl/1"
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
