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
                    "uri": "/hello",
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



=== TEST 3: motify body
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({motify_body = true})
        }
    }
--- error_code: 200
--- response_headers
X-Resp: foo
--- response_body chomp
cat
