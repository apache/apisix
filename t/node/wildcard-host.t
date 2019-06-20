use t::APISix 'no_plan';

no_root_location();

run_tests();

__DATA__

=== TEST 1: host: *.foo.com
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "host": "*.foo.com",
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



=== TEST 3: not found, missing host
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 4: host: a.foo.com
--- request
GET /hello
--- more_headers
Host: a.foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: host: a.b.foo.com
--- request
GET /hello
--- more_headers
Host: a.b.foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: host: .foo.com
--- request
GET /hello
--- more_headers
Host: .foo.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]
