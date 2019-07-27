use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: loaded plugin
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/loaded plugin and sort by priority: [-\d]+ name: [\w-]+/
--- grep_error_log_out
loaded plugin and sort by priority: 2510 name: jwt-auth
loaded plugin and sort by priority: 2500 name: key-auth
loaded plugin and sort by priority: 1003 name: limit-conn
loaded plugin and sort by priority: 1002 name: limit-count
loaded plugin and sort by priority: 1001 name: limit-req
loaded plugin and sort by priority: 1000 name: node-status
loaded plugin and sort by priority: 500 name: prometheus
loaded plugin and sort by priority: 0 name: example-plugin
loaded plugin and sort by priority: -1000 name: zipkin



=== TEST 2: set route(no plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "uri": "/hello",
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



=== TEST 3: hit routes
--- request
GET /hello
--- response_body
hello world
--- response_headers
apisix-plugins: no plugin
--- no_error_log
[error]



=== TEST 4: set route(one plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            },
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
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



=== TEST 5: hit routes
--- request
GET /hello
--- response_body
hello world
--- response_headers
apisix-plugins: limit-conn, limit-count
--- no_error_log
[error]
