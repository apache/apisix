use t::APISix 'no_plan';

repeat_each(2);
log_level('info');
no_root_location();

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
                        "plugins": {},
                        "id":1,
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
--- pipelined_requests eval
["GET /t\n",
"GET /hello\n"]
--- response_body eval
["done\n",
"hello world\n"]
