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
--- no_error_log
[error]



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 3: hit routes
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
