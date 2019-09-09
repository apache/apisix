use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: set global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rule',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/global_rules/1"
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



=== TEST 2: get global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rule',
                ngx.HTTP_GET,
                nil,
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        },
                        "key": "/apisix/global_rules/1"
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



=== TEST 3: delete global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/global_rule',
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



=== TEST 4: delete global rule(not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/global_rule',
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



=== TEST 5: set global rule(invalid host option)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rule',
                ngx.HTTP_PUT,
                [[{
                    "host": "foo.com",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
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
{"error_msg":"invalid configuration: invalid \"additionalProperties\" in docuement at pointer \"#\/host\""}
--- no_error_log
[error]



=== TEST 6: set global rule(missing plugins)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rule',
                ngx.HTTP_PUT,
                [[{}]]
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
