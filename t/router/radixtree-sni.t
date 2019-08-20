use t::APISix 'no_plan';

log_level('debug');
no_root_location();

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/ssl: 'radixtree_uri'/ssl: 'r3_sni'/;

run_tests;

__DATA__

=== TEST 1: set ssl(sni: www.test.com)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("conf/cert/apisix.crt")
        local ssl_key =  t.read_file("conf/cert/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "www.test.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "www.test.com"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: set route(id: 1)
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
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: client request
--- config
location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.test.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET /hello HTTP/1.0\r\nHost: www.test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to receive response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body eval
qr{connected: 1
ssl handshake: userdata
sent http request: 62 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Connection: close
received: Server: openresty
received: \nreceived: hello world
close: 1 nil}
--- error_log
lua ssl server name: "www.test.com"
--- no_error_log
[error]
[alert]



=== TEST 4: client request(no cert domain)
--- config
location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "no-cert.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
        end
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
connected: 1
failed to do SSL handshake: handshake failed
--- error_log
SSL_do_handshake() failed (SSL: error:



=== TEST 5: set ssl(sni: wildcard)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("conf/cert/apisix.crt")
        local ssl_key =  t.read_file("conf/cert/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "*.test.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "*.test.com"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: client request
--- config
location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.test.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET /hello HTTP/1.0\r\nHost: www.test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to receive response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body eval
qr{connected: 1
ssl handshake: userdata
sent http request: 62 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Connection: close
received: Server: openresty
received: \nreceived: hello world
close: 1 nil}
--- error_log
lua ssl server name: "www.test.com"
--- no_error_log
[error]
[alert]



=== TEST 7: set ssl(sni: test.com)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("conf/cert/apisix.crt")
        local ssl_key =  t.read_file("conf/cert/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: client request
--- config
location /t {
    content_by_lua_block {
        -- etcd sync
        ngx.sleep(0.2)

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "test.com", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET /hello HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to receive response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        -- collectgarbage()
    }
}
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body eval
qr{connected: 1
ssl handshake: userdata
sent http request: 58 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Connection: close
received: Server: openresty
received: \nreceived: hello world
close: 1 nil}
--- error_log
lua ssl server name: "test.com"
--- no_error_log
[error]
[alert]
