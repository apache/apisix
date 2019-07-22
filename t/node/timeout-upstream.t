use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(1024);
no_root_location();
no_shuffle();

run_tests();

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
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin",
                            "timeout": {
                                "connect": 0.5,
                                "send": 0.5,
                                "read": 0.5
                            }
                        },
                        "uri": "/sleep1"
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



=== TEST 2: hit routes (timeout)
--- request
GET /sleep1
--- error_code: 504
--- response_body eval
qr/504 Gateway Time-out/
--- error_log
Connection timed out
