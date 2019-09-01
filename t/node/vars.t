use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(only arg_k)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "vars": ["arg_k", "v"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 3: /not_found
--- request
GET /hello?k=not-hit
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 4: hit routes
--- request
GET /hello?k=v
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: set route(cookie)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "vars": ["cookie_k", "v"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 6: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 7: /not_found
--- more_headers
Cookie: k=not-hit; kkk=vvv;
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 8: hit routes
--- more_headers
Cookie: k=v; kkk=vvv;
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 9: set route(header)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "vars": ["http_k", "v"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 10: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 11: /not_found
--- more_headers
k: not-hit
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 12: hit routes
--- more_headers
k: v
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 13: set route(uri arg + header + cookie)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "vars": ["http_k", "header", "cookie_k", "cookie", "arg_k", "uri_arg"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 14: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 15: /not_found
--- more_headers
k: header
--- request
GET /hello
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 16: hit routes
--- more_headers
Cookie: k=cookie
k: header
--- request
GET /hello?k=uri_arg
--- response_body
hello world
--- no_error_log
[error]
