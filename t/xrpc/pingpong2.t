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

    if (!defined $block->extra_stream_config) {
        my $stream_config = <<_EOC_;
    server {
        listen 8125 udp;
        content_by_lua_block {
            require("lib.mock_layer4").dogstatsd()
        }
    }
_EOC_
        $block->set_value("extra_stream_config", $stream_config);
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



=== TEST 2: check the default timeout
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- error_log
stream lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
stream lua tcp socket read timeout: 60000
--- log_level: debug
--- stream_conf_enable



=== TEST 3: bad loggger filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {}
                                },
                                conf = {}
                            }
                        }
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



=== TEST 4: failed to validate the 'filter' expression
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- error_log
failed to validate the 'filter' expression: rule too short



=== TEST 5: set loggger filter(single rule)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 10}
                                },
                                conf = {}
                            }
                        }
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



=== TEST 6: log filter matched successful
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- error_log
log filter: syslog filter result: true



=== TEST 7: update loggger filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", "<", 10}
                                },
                                conf = {}
                            }
                        }
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



=== TEST 8: failed to match log filter
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- error_log
log filter: syslog filter result: false



=== TEST 9: set loggger filter(multiple rules)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 12},
                                    {"rpc_len", "<", 14}
                                },
                                conf = {}
                            }
                        }
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



=== TEST 10: log filter matched successful
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- error_log
log filter: syslog filter result: true



=== TEST 11: update loggger filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", "<", 10},
                                    {"rpc_len", ">", 12}
                                },
                                conf = {}
                            }
                        }
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



=== TEST 12: failed to match log filter
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- error_log
log filter: syslog filter result: false



=== TEST 13: set custom log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/syslog',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "client_ip": "$remote_addr"
                    }
                }]]
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



=== TEST 14: no loggger filter, defaulte executed logger plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                conf = {
                                    host = "127.0.0.1",
                                    port = 8125,
                                    sock_type = "udp",
                                    batch_max_size = 1,
                                    flush_limit = 1
                                }
                            }
                        }
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



=== TEST 15: verify the data received by the log server
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- wait: 0.5
--- error_log eval
qr/message received:.*\"client_ip\"\:\"127.0.0.1\"/



=== TEST 16: set loggger filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 10}
                                },
                                conf = {
                                    host = "127.0.0.1",
                                    port = 8125,
                                    sock_type = "udp",
                                    batch_max_size = 1,
                                    flush_limit = 1
                                }
                            }
                        }
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



=== TEST 17: verify the data received by the log server
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- stream_conf_enable
--- wait: 0.5
--- error_log eval
qr/message received:.*\"client_ip\"\:\"127.0.0.1\"/



=== TEST 18: small flush_limit, instant flush
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 10}
                                },
                                conf = {
                                    host = "127.0.0.1",
                                    port = 5044,
                                    batch_max_size = 1,
                                    flush_limit = 1
                                }
                            }
                        }
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

            -- wait etcd sync
            ngx.sleep(0.5)

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            assert(sock:send("pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"))

            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
            -- wait flush log
            ngx.sleep(2.5)
        }
    }
--- request
GET /t
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- timeout: 5
--- error_log
try to lock with key xrpc-pingpong-logger#table
unlock with key xrpc-pingpong-logger#table



=== TEST 19: check plugin configuration updating
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 10}
                                },
                                conf = {
                                    host = "127.0.0.1",
                                    port = 5044,
                                    batch_max_size = 1
                                }
                            }
                        }
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
                ngx.say("fail")
                return
            end
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.status = code
                ngx.say("fail")
                return
            end
            assert(sock:send("pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"))
            local body1, err
            while true do
                body1, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
            end
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong",
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_len", ">", 10}
                                },
                                conf = {
                                    host = "127.0.0.1",
                                    port = 5045,
                                    batch_max_size = 1
                                }
                            }
                        }
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
                ngx.say("fail")
                return
            end
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.status = code
                ngx.say("fail")
                return
            end
            assert(sock:send("pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"))
            local body2, err
            while true do
                body2, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
            end
            ngx.print(body1)
            ngx.print(body2)
        }
    }
--- request
GET /t
--- wait: 0.5
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- grep_error_log eval
qr/sending a batch logs to 127.0.0.1:(\d+)/
--- grep_error_log_out
sending a batch logs to 127.0.0.1:5044
sending a batch logs to 127.0.0.1:5045
