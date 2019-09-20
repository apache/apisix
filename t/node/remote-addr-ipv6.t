use t::APISIX;

no_root_location();

my $travis_os_name = $ENV{TRAVIS_OS_NAME};
if ($travis_os_name eq "osx") {
    plan 'no_plan';
} else {
    plan(skip_all => "skip remote address(IPv6) under linux");
}

run_tests();

__DATA__

=== TEST 1: set route: remote addr = ::1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "remote_addr": "::1",
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



=== TEST 2: IPv6 /not_found
--- listen_ipv6
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.2)
        local t = require("lib.test_admin").test_ipv6
        t('/not_found')
    }
}
--- request
GET /t
--- response_body_like eval
qr{.*404 Not Found.*}
--- no_error_log
[error]



=== TEST 3: IPv4 /not_found
--- listen_ipv6
--- request
GET /not_found
--- error_code: 404
--- response_body_like eval
qr{.*404 Not Found.*}
--- no_error_log
[error]



=== TEST 4: IPv6 /hello
--- listen_ipv6
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.2)
        local t = require("lib.test_admin").test_ipv6
        t('/hello')
    }
}
--- request
GET /t
--- response_body
connected: 1
request sent: 59
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Connection: close
received: Server: openresty
received: 
received: hello world
failed to receive a line: closed []
close: 1 nil
--- no_error_log
[error]



=== TEST 5: IPv4 /hello
--- listen_ipv6
--- request
GET /hello
--- error_code: 404
--- response_body_like eval
qr{.*404 Not Found.*}
--- no_error_log
[error]
