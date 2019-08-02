use t::APISix 'no_plan';

worker_connections(256);
no_root_location();

run_tests();

__DATA__

=== TEST 1: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
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



=== TEST 2: set route (different upstream)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 3: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 4: hit routes
--- request
GET /server_port
--- response_headers
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
--- response_body eval
qr/1981/
--- no_error_log
[error]



=== TEST 5: set route with empty plugins, should do nothing
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {},
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 6: hit routes
--- request
GET /server_port
--- response_headers
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
--- response_body eval
qr/1980/
--- no_error_log
[error]



=== TEST 7: disable plugin `limit-count`
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "disable": true
                        }
                    },
                    "uri": "/server_port",
                    "service_id": 1
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



=== TEST 8: hit routes
--- request
GET /server_port
--- raw_response_headers_unlike eval
qr/X-RateLimit-Limit/
--- response_body eval
qr/1980/
--- no_error_log
[error]
