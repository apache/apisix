use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
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
                    "uri": "/hello",
                    "remote_addrs": ["192.0.0.0/8", "127.0.0.3"],
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
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /not_found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 3: /not_found
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
Host: not_found.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 4: hit routes
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
X-Real-IP: 192.168.1.100
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: hit routes
--- http_config
real_ip_header X-Real-IP;
set_real_ip_from 127.0.0.1;
set_real_ip_from unix:;
--- request
GET /hello
--- more_headers
X-Real-IP: 127.0.0.3
--- response_body
hello world
--- no_error_log
[error]
