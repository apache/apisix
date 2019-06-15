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
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- request
GET /not_found
--- error_code eval
[200, 404]
--- pipelined_requests eval
["GET /t\n",
"GET /not_found\n"]
--- response_body eval
["done\n",
 qr/404 Not Found/]



=== TEST 3: hit routes
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- error_code eval
[200, 502]
--- pipelined_requests eval
["GET /t\n",
"GET /hello\n"]
--- response_body eval
["done\n",
qr/502 Bad Gateway/]
