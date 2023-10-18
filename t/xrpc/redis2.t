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

log_level("warn");

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

$ENV{TEST_NGINX_REDIS_PORT} ||= 1985;

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: redis
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\nRPC is not finished");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
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

worker_connections(1024);
run_tests;

__DATA__

=== TEST 1: set custom log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/syslog',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "rpc_time": "$rpc_time",
                        "redis_cmd_line": "$redis_cmd_line"
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



=== TEST 2: use register vars(redis_cmd_line and rpc_time) in logger
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.01, commands = {"hmset", "hmget", "ping"}},
                            }
                        },
                        logger = {
                            {
                                name = "syslog",
                                filter = {
                                    {"rpc_time", ">=", 0.001},
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
--- response_body
passed



=== TEST 3: verify the data received by the log server
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:hmset("animals", "dog", "bark", "cat", "meow")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = red:hmget("animals", "dog", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            -- test for only one command in cmd_line
            local res, err = red:ping()
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("ping: ", string.lower(res))
        }
    }
--- response_body
hmset animals: OK
hmget animals: barkmeow
ping: pong
--- wait: 1
--- grep_error_log eval
qr/message received:.*\"redis_cmd_line\":[^}|^,]+/
--- grep_error_log_out eval
qr{message received:.*\"redis_cmd_line\":\"hmset animals dog bark cat meow\"(?s).*
message received:.*\"redis_cmd_line\":\"hmget animals dog cat\"(?s).*
message received:.*\"redis_cmd_line\":\"ping\"}
