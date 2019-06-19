use t::APISix 'no_plan';

repeat_each(1);
no_root_location();

run_tests();

__DATA__

=== TEST 1: set upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                }]],
                [[{
                    "node": {
                        "value": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "key": "/apisix/upstreams/1"
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



=== TEST 2: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream_id": 1
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream_id": 1
                        },
                        "key": "/apisix/services/1"
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



=== TEST 3: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream_id": 1,
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream_id": 1,
                            "uri": "/index.html"
                        },
                        "key": "/apisix/routes/1"
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



=== TEST 4: delete upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
                )
            ngx.print("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 400 message: {"error_msg":"can not delete this upstream, route [1] is still using it now"}
--- no_error_log
[error]



=== TEST 5: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
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



=== TEST 6: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
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



=== TEST 7: delete upstream(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{"action": "delete"}]]
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
