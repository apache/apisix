use t::APISIX 'no_plan';

log_level('info');
no_root_location();

run_tests();

__DATA__

=== TEST 1: create stream route with a upstream that enable active healthcheck only, \
            two upstream nodes: one healthy + one unhealthy, unhealthy node with high priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": [
                            { "host": "127.0.0.1", "port": 1995, "weight": 100, "priority": 0 },
                            { "host": "127.0.0.1", "port": 9995, "weight": 100, "priority": 1 }
                        ],
                        "type": "roundrobin",
                        "retries": 0,
                        "checks": {
                            "active": {
                                "type": "tcp",
                                "timeout": 1,
                                "healthy": {
                                    "interval": 1,
                                    "successes": 2
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "tcp_failures": 1,
                                    "timeouts": 1
                                }
                            }
                        }
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



=== TEST 2: hit stream routes
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            -- send first request to create health checker
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            local data, _ = sock:receive()
            assert(data == nil, "first request should fail")
            sock:close()

            -- wait for health check to take effect
            ngx.sleep(2.5)

            for i = 1, 3 do
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", 1985)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local _, err = sock:send("mmm")
                if err then
                    ngx.say("failed to send: ", err)
                    return
                end

                local data, err = sock:receive()
                if err then
                    ngx.say("failed to receive: ", err)
                    return
                end

                assert(data == "hello world", "response should be 'hello world'")

                sock:close()
            end

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_DELETE
            )

            if code >= 300 then
                ngx.status = code
                ngs.say("failed to delete stream route")
                return
            end

            -- wait for checker to release
            ngx.sleep(1)

            ngx.say("passed")
        }
    }
--- timeout: 10
--- request
GET /t
--- response_body
passed
--- error_log
create new checker
proxy request to 127.0.0.1:9995 while connecting to upstream
connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: 0.0.0.0:1985, upstream: "127.0.0.1:9995"
unhealthy TCP increment (1/1) for '(127.0.0.1:9995)'
proxy request to 127.0.0.1:1995 while connecting to upstream
proxy request to 127.0.0.1:1995 while connecting to upstream
proxy request to 127.0.0.1:1995 while connecting to upstream
try to release checker



=== TEST 3: create stream route with a upstream that enable active and passive healthcheck, \
            configure active healthcheck with a high unhealthy threshold, \
            two upstream nodes: one healthy + one unhealthy, unhealthy node with high priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": [
                            { "host": "127.0.0.1", "port": 1995, "weight": 100, "priority": 0 },
                            { "host": "127.0.0.1", "port": 9995, "weight": 100, "priority": 1 }
                        ],
                        "type": "roundrobin",
                        "retries": 0,
                        "checks": {
                            "active": {
                                "type": "tcp",
                                "timeout": 1,
                                "healthy": {
                                    "interval": 60,
                                    "successes": 2
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "tcp_failures": 254,
                                    "timeouts": 1
                                }
                            },
                            "passive": {
                                "type": "tcp",
                                "healthy": {
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "tcp_failures": 1
                                }
                            }
                        }
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



=== TEST 4: hit stream routes
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            local data, _ = sock:receive()
            assert(data == nil, "first request should fail")
            sock:close()

            for i = 1, 3 do
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", 1985)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local _, err = sock:send("mmm")
                if err then
                    ngx.say("failed to send: ", err)
                    return
                end

                local data, err = sock:receive()
                if err then
                    ngx.say("failed to receive: ", err)
                    return
                end

                assert(data == "hello world", "response should be 'hello world'")

                sock:close()
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
proxy request to 127.0.0.1:9995 while connecting to upstream
connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: 0.0.0.0:1985, upstream: "127.0.0.1:9995"
enabled healthcheck passive while connecting to upstream, client: 127.0.0.1, server: 0.0.0.0:1985, upstream: "127.0.0.1:9995",
unhealthy TCP increment (1/1) for '(127.0.0.1:9995)' while connecting to upstream, client: 127.0.0.1, server: 0.0.0.0:1985, upstream: "127.0.0.1:9995",
proxy request to 127.0.0.1:1995 while connecting to upstream
proxy request to 127.0.0.1:1995 while connecting to upstream
proxy request to 127.0.0.1:1995 while connecting to upstream
