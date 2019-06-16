use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_long_string();
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: invalid service id
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/routes/1", {
                    service_id = "999999999",
                    uri = "/hello"
                })


            if res.status >= 300 then
                ngx.status = res.status
                return ngx.exit(res.status)
            end
            ngx.say("passed")
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
GET /hello
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
--- wait_etcd_sync: 0.3
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/failed to fetch service configuration by id/



=== TEST 3: set valid route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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



=== TEST 4: hit routes
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
