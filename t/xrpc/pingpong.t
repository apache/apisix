#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: pingpong
    - name: redis
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $config = $block->config // <<_EOC_;
    location /t {
        content_by_lua_block {
            ngx.req.read_body()
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            local bytes, err = sock:send(ngx.req.get_body_data())
            if not bytes then
                ngx.log(ngx.ERR, "send stream request error: ", err)
                return ngx.exit(503)
            end
            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    my $stream_upstream_code = $block->stream_upstream_code // <<_EOC_;
            local sock = ngx.req.socket(true)
            sock:settimeout(10)
            while true do
                local data = sock:receiveany(4096)
                if not data then
                    return
                end
                sock:send(data)
            end
_EOC_

    $block->set_value("stream_upstream_code", $stream_upstream_code);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\nRPC is not finished");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: init
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 2: too short
--- stream_request
mmm
--- error_log
call pingpong's init_worker
failed to read: timeout



=== TEST 3: reply directly
--- request eval
"POST /t
pp\x01\x00\x00\x00\x00\x00\x00\x00"
--- response_body eval
"pp\x01\x00\x00\x00\x00\x00\x00\x00"
--- stream_conf_enable



=== TEST 4: unary
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC" x 3
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC" x 3
--- log_level: debug
--- no_error_log
stream lua tcp socket set keepalive
--- stream_conf_enable



=== TEST 5: unary & heartbeat
--- request eval
"POST /t
" .
"pp\x01\x00\x00\x00\x00\x00\x00\x00" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- response_body eval
"pp\x01\x00\x00\x00\x00\x00\x00\x00" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable



=== TEST 6: can't connect to upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1979"] = 1
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 7: hit
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC" x 3
--- error_log
failed to connect: connection refused
--- stream_conf_enable



=== TEST 8: use short timeout to check upstream's bad response
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1995"] = 1
                        },
                        timeout = {
                            connect = 0.01,
                            send = 0.009,
                            read = 0.008,
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 9: bad response
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC" x 1
--- stream_conf_enable
--- stream_upstream_code
    local sock = ngx.req.socket(true)
    sock:settimeout(10)
    while true do
        local data = sock:receiveany(4096)
        if not data then
            return
        end
        sock:send(data:sub(5))
    end
--- error_log
failed to read: timeout
stream lua tcp socket connect timeout: 10
lua tcp socket send timeout: 9
stream lua tcp socket read timeout: 8
--- log_level: debug



=== TEST 10: reset
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 11: client stream, N:N
--- request eval
"POST /t
" .
"pp\x03\x00\x01\x00\x00\x00\x00\x03ABC" .
"pp\x03\x00\x02\x00\x00\x00\x00\x04ABCD"
--- stream_conf_enable
--- stream_upstream_code
    local sock = ngx.req.socket(true)
    sock:settimeout(10)
    local data1 = sock:receive(13)
    if not data1 then
        return
    end
    local data2 = sock:receive(14)
    if not data2 then
        return
    end
    assert(sock:send(data2))
    assert(sock:send(data1))
--- response_body eval
"pp\x03\x00\x02\x00\x00\x00\x00\x04ABCD" .
"pp\x03\x00\x01\x00\x00\x00\x00\x03ABC"



=== TEST 12: client stream, bad response
--- request eval
"POST /t
" .
"pp\x03\x00\x01\x00\x00\x00\x00\x03ABC" .
"pp\x03\x00\x02\x00\x00\x00\x00\x04ABCD"
--- stream_conf_enable
--- stream_upstream_code
    local sock = ngx.req.socket(true)
    sock:settimeout(10)
    local data1 = sock:receive(13)
    if not data1 then
        return
    end
    local data2 = sock:receive(14)
    if not data2 then
        return
    end
    assert(sock:send(data2))
    assert(sock:send(data1:sub(11)))
--- response_body eval
"pp\x03\x00\x02\x00\x00\x00\x00\x04ABCD"
--- error_log
RPC is not finished
call pingpong's log, ctx unfinished: true



=== TEST 13: server stream, heartbeat
--- request eval
"POST /t
" .
"pp\x03\x00\x01\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- stream_upstream_code
    local sock = ngx.req.socket(true)
    sock:settimeout(10)
    local data1 = sock:receive(13)
    if not data1 then
        return
    end
    local hb = "pp\x01\x00\x00\x00\x00\x00\x00\x00"
    assert(sock:send(hb))
    local data2 = sock:receive(10)
    if not data2 then
        return
    end
    assert(data2 == hb)
    assert(sock:send(data1))
--- response_body eval
"pp\x03\x00\x01\x00\x00\x00\x00\x03ABC"



=== TEST 14: server stream
--- request eval
"POST /t
" .
"pp\x03\x00\x01\x00\x00\x00\x00\x01A"
--- stream_conf_enable
--- stream_upstream_code
    local sock = ngx.req.socket(true)
    sock:settimeout(10)
    local data1 = sock:receive(11)
    if not data1 then
        return
    end
    assert(sock:send("pp\x03\x00\x03\x00\x00\x00\x00\x03ABC"))
    assert(sock:send("pp\x03\x00\x02\x00\x00\x00\x00\x02AB"))
    assert(sock:send(data1))
--- response_body eval
"pp\x03\x00\x03\x00\x00\x00\x00\x03ABC" .
"pp\x03\x00\x02\x00\x00\x00\x00\x02AB" .
"pp\x03\x00\x01\x00\x00\x00\x00\x01A"
--- grep_error_log eval
qr/call pingpong's log, ctx unfinished: \w+/
--- grep_error_log_out
call pingpong's log, ctx unfinished: false
call pingpong's log, ctx unfinished: false
call pingpong's log, ctx unfinished: false



=== TEST 15: superior & subordinate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.3:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        superior_id = 1,
                        conf = {
                            service = "a"
                        },
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/3',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        superior_id = 1,
                        conf = {
                            service = "b"
                        },
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.2:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- routes below should not be used to matched
            local code, body = t('/apisix/admin/stream_routes/4',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        superior_id = 10000,
                        conf = {
                            service = "b"
                        },
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.2:1979"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/5',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:6379"] = 1
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 16: hit
--- request eval
"POST /t
" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04b\x00\x00\x00ABCD" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"
--- response_body eval
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04b\x00\x00\x00ABCD" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"
--- grep_error_log eval
qr/connect to \S+ while prereading client data/
--- grep_error_log_out
connect to 127.0.0.1:1995 while prereading client data
connect to 127.0.0.2:1995 while prereading client data
--- stream_conf_enable



=== TEST 17: hit (fallback to superior if not found)
--- request eval
"POST /t
" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03abcdABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03abcdABC"
--- response_body eval
"pp\x04\x00\x00\x00\x00\x00\x00\x03abcdABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03abcdABC"
--- grep_error_log eval
qr/connect to \S+ while prereading client data/
--- grep_error_log_out
connect to 127.0.0.3:1995 while prereading client data
connect to 127.0.0.1:1995 while prereading client data
--- stream_conf_enable



=== TEST 18: cache router by version
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            assert(sock:send("pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"))

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        superior_id = 1,
                        conf = {
                            service = "c"
                        },
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.4:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local s = "pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD"
            assert(sock:send(s .. "pp\x04\x00\x00\x00\x00\x00\x00\x03c\x00\x00\x00ABC"))

            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
--- request
GET /t
--- response_body eval
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03c\x00\x00\x00ABC"
--- grep_error_log eval
qr/connect to \S+ while prereading client data/
--- grep_error_log_out
connect to 127.0.0.1:1995 while prereading client data
connect to 127.0.0.3:1995 while prereading client data
connect to 127.0.0.4:1995 while prereading client data
--- stream_conf_enable



=== TEST 19: use upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                {
                    nodes = {
                        ["127.0.0.3:1995"] = 1
                    },
                    type = "roundrobin"
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        superior_id = 1,
                        conf = {
                            service = "a"
                        },
                        name = "pingpong"
                    },
                    upstream_id = 1
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 20: hit
--- request eval
"POST /t
" .
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"
--- response_body eval
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"
--- grep_error_log eval
qr/connect to \S+ while prereading client data/
--- grep_error_log_out
connect to 127.0.0.3:1995 while prereading client data
--- stream_conf_enable



=== TEST 21: cache router by version, with upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            assert(sock:send("pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC"))

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                {
                    nodes = {
                        ["127.0.0.1:1995"] = 1
                    },
                    type = "roundrobin"
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local s = "pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD"
            assert(sock:send(s))

            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
--- request
GET /t
--- response_body eval
"pp\x04\x00\x00\x00\x00\x00\x00\x03a\x00\x00\x00ABC" .
"pp\x04\x00\x00\x00\x00\x00\x00\x04a\x00\x00\x00ABCD"
--- grep_error_log eval
qr/connect to \S+ while prereading client data/
--- grep_error_log_out
connect to 127.0.0.3:1995 while prereading client data
connect to 127.0.0.1:1995 while prereading client data
--- stream_conf_enable
