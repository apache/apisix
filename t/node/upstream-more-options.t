use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(more upstream options)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/old_uri",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "scheme": "http",
                        "host": "foo.com",
                        "upgrade": "upgrade.com",
                        "connection": "connection.com",
                        "uri": "/uri"
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



=== TEST 2: hit routes
--- request
GET /old_uri
--- response_body
uri: /uri
host: foo.com
upgrade: upgrade.com
connection: connection.com
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 3: set route(enable websocket)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/old_uri",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "scheme": "http",
                        "host": "foo.com",
                        "enable_websocket": true,
                        "uri": "/uri"
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



=== TEST 4: hit routes
--- more_headers
upgrade: upgrade
connection: close
--- request
GET /old_uri
--- response_body
uri: /uri
host: foo.com
upgrade: upgrade
connection: close
x-real-ip: 127.0.0.1
--- no_error_log
[error]
