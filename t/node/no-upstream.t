use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
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
                    "plugins": {},
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
--- response_body_like eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 3: hit routes
--- request
GET /hello
--- error_code: 502
--- response_body eval
qr/502 Bad Gateway/
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/failed to pick server: missing upstream configuration while connecting to upstream/
