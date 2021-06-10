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

$ENV{"PATH"} = $ENV{PATH} . ":" . $ENV{TEST_NGINX_HTML_DIR};

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
    my $orig_extra_yaml_config = $block->extra_yaml_config // "";
    my $cmd = $block->ext_plugin_cmd // "['sleep', '5s']";
    my $extra_yaml_config = <<_EOC_;
ext-plugin:
    path_for_test: $unix_socket_path
    cmd: $cmd
_EOC_
    $extra_yaml_config = $extra_yaml_config . $orig_extra_yaml_config;

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

=== TEST 1: sanity
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
                        "ext-plugin-pre-req": {},
                        "ext-plugin-post-req": {}
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



=== TEST 2: hit
--- request
GET /hello
--- response_body
hello world
--- error_log
get conf token: 233
--- no_error_log
[error]
flush conf token lrucache
--- grep_error_log eval
qr/(sending|receiving) rpc type: \d data length:/
--- grep_error_log_out
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
sending rpc type: 2 data length:
receiving rpc type: 2 data length:
sending rpc type: 2 data length:
receiving rpc type: 2 data length:
sending rpc type: 2 data length:
receiving rpc type: 2 data length:
sending rpc type: 2 data length:
receiving rpc type: 2 data length:



=== TEST 3: header too short
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.header_too_short()
        }
    }
--- request
GET /hello
--- error_code: 503
--- error_log
failed to receive RPC_PREPARE_CONF



=== TEST 4: data too short
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.data_too_short()
        }
    }
--- request
GET /hello
--- error_code: 503
--- error_log
failed to receive RPC_PREPARE_CONF



=== TEST 5: not listen
--- extra_stream_config
--- request
GET /hello
--- error_code: 503
--- error_log
failed to connect to the unix socket



=== TEST 6: spawn runner
--- ext_plugin_cmd
["t/plugin/ext-plugin/runner.sh", "3600"]
--- config
    location /t {
        access_by_lua_block {
            -- ensure the runner is spawned before the request finishes
            ngx.sleep(0.1)
            ngx.exit(200)
        }
    }
--- grep_error_log eval
qr/LISTEN unix:\S+/
--- grep_error_log_out eval
qr/LISTEN unix:.+\/nginx.sock/
--- error_log
EXPIRE 3600



=== TEST 7: respawn runner when it exited
--- ext_plugin_cmd
["t/plugin/ext-plugin/runner.sh", "0.1"]
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.2)
        }
    }
--- error_log
runner exited with reason: exit, status: 111
respawn runner 3 seconds later with cmd: ["t\/plugin\/ext-plugin\/runner.sh","0.1"]



=== TEST 8: flush cache when runner exited
--- ext_plugin_cmd
["t/plugin/ext-plugin/runner.sh", "0.4"]
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local function r()
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.log(ngx.ERR, err)
                    return
                else
                    ngx.print(res.body)
                end
            end

            r()
            r()
            ngx.sleep(0.5)
            r()
        }
    }
--- response_body
hello world
hello world
hello world
--- grep_error_log eval
qr/(sending|receiving) rpc type: 1 data length:/
--- grep_error_log_out
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
sending rpc type: 1 data length:
receiving rpc type: 1 data length:
--- error_log
flush conf token lrucache
--- no_error_log
[error]



=== TEST 9: prepare conf
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
                            "conf": [
                                {"name":"foo", "value":"bar"},
                                {"name":"cat", "value":"dog"}
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



=== TEST 10: hit
--- request
GET /hello
--- response_body
hello world
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({with_conf = true})
        }
    }
--- error_log eval
qr/get conf token: 233 conf: \[(\{"value":"bar","name":"foo"\}|\{"name":"foo","value":"bar"\}),(\{"value":"dog","name":"cat"\}|\{"name":"cat","value":"dog"\})\]/
--- no_error_log
[error]



=== TEST 11: handle error code
--- request
GET /hello
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({inject_error = true})
        }
    }
--- error_code: 503
--- error_log
failed to receive RPC_PREPARE_CONF: bad request



=== TEST 12: refresh token
--- request
GET /hello
--- response_body
hello world
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            if not package.loaded.count then
                package.loaded.count = 1
            else
                package.loaded.count = package.loaded.count + 1
            end

            if package.loaded.count == 1 then
                ext.go({no_token = true})
            else
                ext.go({with_conf = true})
            end
        }
    }
--- error_log
refresh cache and try again
--- no_error_log
[error]



=== TEST 13: runner can access the environment variable
--- main_config
env MY_ENV_VAR=foo;
--- ext_plugin_cmd
["t/plugin/ext-plugin/runner.sh", "3600"]
--- config
    location /t {
        access_by_lua_block {
            -- ensure the runner is spawned before the request finishes
            ngx.sleep(0.1)
            ngx.exit(200)
        }
    }
--- error_log
MY_ENV_VAR foo



=== TEST 14: bad conf
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
                            "conf": [
                                {"value":"bar"}
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
                ngx.say(message)
            end

            local code, message, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "plugins": {
                        "ext-plugin-post-req": {
                            "conf": [
                                {"name":"bar"}
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
                ngx.print(message)
            end
        }
    }
--- response_body
{"error_msg":"failed to check the configuration of plugin ext-plugin-pre-req err: property \"conf\" validation failed: failed to validate item 1: property \"name\" is required"}

{"error_msg":"failed to check the configuration of plugin ext-plugin-post-req err: property \"conf\" validation failed: failed to validate item 1: property \"value\" is required"}
