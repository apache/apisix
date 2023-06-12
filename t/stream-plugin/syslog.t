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
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
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

});

run_tests;

__DATA__

=== TEST 1: custom log format not set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- ensure the format is not set
            t('/apisix/admin/plugin_metadata/syslog',
                ngx.HTTP_DELETE
                )

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "syslog": {
                            "host" : "127.0.0.1",
                            "port" : 8125,
                            "sock_type": "udp",
                            "batch_max_size": 1,
                            "flush_limit":1
                        }
                    },
                    "upstream_id": "1"
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



=== TEST 2: hit
--- stream_request eval
mmm
--- stream_response
hello world
--- error_log
syslog's log_format is not set



=== TEST 3: set custom log format
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



=== TEST 4: hit
--- stream_request eval
mmm
--- stream_response
hello world
--- wait: 0.5
--- error_log eval
qr/message received:.*\"client_ip\\"\:\\"127.0.0.1\\"/



=== TEST 5: flush manually
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.stream.plugins.syslog")
            local logger_socket = require("resty.logger.socket")
            local logger, err = logger_socket:new({
                    host = "127.0.0.1",
                    port = 5044,
                    flush_limit = 100,
            })

            local bytes, err = logger:log("abc")
            if err then
                ngx.log(ngx.ERR, err)
            end

            local bytes, err = logger:log("efg")
            if err then
                ngx.log(ngx.ERR, err)
            end

            local ok, err = plugin.flush_syslog(logger)
            if not ok then
                ngx.say("failed to flush syslog: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 6: small flush_limit, instant flush
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5044,
                                "flush_limit" : 1,
                                "inactive_timeout": 1
                            }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            -- wait etcd sync
            ngx.sleep(0.5)

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            assert(sock:send("mmm"))
            local data = assert(sock:receive("*a"))
            ngx.print(data)

            -- wait flush log
            ngx.sleep(2.5)
        }
    }
--- request
GET /t
--- response_body
passed
hello world
--- timeout: 5
--- error_log
try to lock with key stream/route#1
unlock with key stream/route#1



=== TEST 7: check plugin configuration updating
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body1 = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5044,
                                "batch_max_size": 1
                            }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
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

            assert(sock:send("mmm"))
            local body2 = assert(sock:receive("*a"))

            local code, body3 = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5045,
                                 "batch_max_size": 1
                            }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
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

            assert(sock:send("mmm"))
            local body4 = assert(sock:receive("*a"))

            ngx.print(body1)
            ngx.print(body2)
            ngx.print(body3)
            ngx.print(body4)
        }
    }
--- request
GET /t
--- wait: 0.5
--- response_body
passedhello world
passedhello world
--- grep_error_log eval
qr/sending a batch logs to 127.0.0.1:(\d+)/
--- grep_error_log_out
sending a batch logs to 127.0.0.1:5044
sending a batch logs to 127.0.0.1:5045



=== TEST 8: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "flush_limit": 1,
                                "log_format": {
                                    "vip": "$remote_addr"
                                },
                                "host" : "127.0.0.1",
                                "port" : 5050
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1995": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 9: access
--- stream_extra_init_by_lua
    local syslog = require("apisix.plugins.syslog.init")
    local json = require("apisix.core.json")
    local log = require("apisix.core.log")
    local old_f = syslog.push_entry
    syslog.push_entry = function(conf, ctx, entry)
        assert(entry.vip == "127.0.0.1")
        log.info("push_entry is called with data: ", json.encode(entry))
        return old_f(conf, ctx, entry)
    end
--- stream_request
mmm
--- stream_response
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log
push_entry is called with data
