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
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("stream_conf_enable", 1);

    if (!defined $block->extra_stream_config) {
        my $stream_config = <<_EOC_;
    server {
        listen unix:\$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({})
        }
    }

_EOC_
        $block->set_value("extra_stream_config", $stream_config);
    }

    my $unix_socket_path = $ENV{"TEST_NGINX_HTML_DIR"} . "/nginx.sock";
    my $cmd = $block->ext_plugin_cmd // "['sleep', '5s']";
    my $extra_yaml_config = <<_EOC_;
ext-plugin:
    path_for_test: $unix_socket_path
    cmd: $cmd
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: add route
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/*",
                    "plugins": {
                        "ext-plugin-post-resp": {
                        }
                    },
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
                ngx.say(message)
                return
            end

            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 2: check input
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({check_input = true})
        }
    }
--- error_code: 200
--- response_body
hello world



=== TEST 3: modify body
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({modify_body = true})
        }
    }
--- error_code: 200
--- response_body chomp
cat



=== TEST 4: modify header
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({modify_header = true})
        }
    }
--- more_headers
resp-X-Runner: Go-runner
--- error_code: 200
--- response_headers
X-Runner: Test-Runner
Content-Type: application/json
--- response_body
hello world



=== TEST 5: modify same response headers
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({modify_header = true, same_header = true})
        }
    }
--- error_code: 200
--- response_headers
X-Same: one, two
--- response_body
hello world



=== TEST 6: modify status
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({modify_status = true})
        }
    }
--- error_code: 304



=== TEST 7: default allow_degradation
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "plugins": {
                        "ext-plugin-post-resp": {
                            "conf": [
                                {"name":"foo", "value":"bar"}
                            ]
                        }
                    },
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
                ngx.say(message)
                return
            end

            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 8: ext-plugin-resp wrong, req reject
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock1;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({})
        }
    }
--- error_code: 503
--- error_log eval
qr/failed to connect to the unix socket/



=== TEST 9: open allow_degradation
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "plugins": {
                        "ext-plugin-post-req": {
                            "conf": [
                                {"name":"foo", "value":"bar"}
                            ],
                            "allow_degradation": true
                        }
                    },
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
                ngx.say(message)
                return
            end

            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 10: ext-plugin-resp wrong, req access
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock1;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({})
        }
    }
--- response_body
hello world
--- error_log eval
qr/Plugin Runner.*allow degradation/



=== TEST 11: add route: wrong upstream
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/*",
                    "plugins": {
                        "ext-plugin-post-resp": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:3980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 12: request upstream failed
--- request
GET /hello
--- error_code: 502
--- error_log eval
qr/failed to request/



=== TEST 13: add route
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/*",
                    "plugins": {
                        "ext-plugin-post-resp": {
                        }
                    },
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
                ngx.say(message)
                return
            end

            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 14: body_reader error
--- request
GET /hello1
--- more_headers
resp-Content-Length: 14
--- error_code: 502
--- error_log eval
qr/read response failed/



=== TEST 15: response chunked
--- request
GET /hello_chunked
--- error_code: 200
--- response_body
hello world



=== TEST 16: check upstream uri with args
--- request
GET /plugin_proxy_rewrite_args?aaa=bbb&ccc=ddd
--- error_code: 200
--- response_body
uri: /plugin_proxy_rewrite_args
aaa: bbb
ccc: ddd
