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
use Cwd qw(cwd);

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

my $apisix_home = $ENV{APISIX_HOME} || cwd();

sub read_file($) {
    my $infile = shift;
    open my $in, "$apisix_home/$infile"
        or die "cannot open $infile for reading: $!";
    my $data = do { local $/; <$in> };
    close $in;
    $data;
}

my $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/  # stream_proxy:/  stream_proxy:\n    tcp:\n      - 9100/;
$yaml_config =~ s/admin_key:/admin_key_useless:/;

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = $block->yaml_config;
    $user_yaml_config .= <<_EOC_;
$yaml_config
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.1",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new route"
                        },
                        "key": "/apisix/stream_routes/1"
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
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: get route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.1",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new route"
                        },
                        "key": "/apisix/stream_routes/1"
                    },
                    "action": "get"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_DELETE,
                nil,
                [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: post route + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/stream_routes',
                ngx.HTTP_POST,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.1",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new route"
                        }
                    },
                    "action": "create"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/stream_routes/" + 1)
            code, message = t('/apisix/admin/stream_routes/' .. id,
                ngx.HTTP_DELETE,
                nil,
                [[{
                    "action": "delete"
                }]]
            )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 5: set route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4,
                            "upstream": {
                                "ip": "127.0.0.1",
                                "port": 1980
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
--- no_error_log
[error]



=== TEST 6: set route with server_addr and server_port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_addr": "127.0.0.1",
                    "server_port": 1982,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4,
                            "upstream": {
                                "ip": "127.0.0.1",
                                "port": 1980
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
--- no_error_log
[error]



=== TEST 7: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_DELETE,
                nil,
                [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]
