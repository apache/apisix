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
log_level("info");

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

=== TEST 1: add route with ext-plugin-pre-req
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
                        "ext-plugin-pre-req": {
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
--- no_error_log
[error]



=== TEST 2: test URI args processing with rewrite - path and args
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite = true})
        }
    }
--- request
GET /hello?original=param&test=value
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: test URI args processing with rewrite - args only
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args_only = true})
        }
    }
--- request
GET /hello?original=param&test=value
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: test URI args processing with complex args modification
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args = true})
        }
    }
--- request
GET /hello?a=1&b=2&c=3
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: test URI args processing with path rewrite and args
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite = true})
        }
    }
--- request
GET /hello?x=1&y=2&z=3
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: test URI args processing with empty args
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args_only = true})
        }
    }
--- request
GET /hello
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: test URI args processing with multiple same name args
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args = true})
        }
    }
--- request
GET /hello?a=1&a=2&b=3
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: test URI args processing with args containing special characters
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args_only = true})
        }
    }
--- request
GET /hello?param=value%20with%20spaces&encoded=%26%3D%3F
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: test URI args processing with path rewrite only
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite = true})
        }
    }
--- request
GET /hello?keep=this&param=value
--- response_body
passed
--- no_error_log
[error]



=== TEST 10: test URI args processing with args deletion
--- config
    location /t {
        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite_args = true})
        }
    }
--- request
GET /hello?delete=me&keep=this&remove=too
--- response_body
passed
--- no_error_log
[error]
