use t::APISIX 'no_plan';

repeat_each(1);
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "httpbin.org:80": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/get"
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
--- error_code: 200



=== TEST 2: hit route
--- request
GET /get
--- error_code: 200
--- no_error_log
[error]



=== TEST 3: not hit route
--- request
GET /post
--- error_code: 404
--- no_error_log
[error]
