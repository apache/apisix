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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
wasm:
    plugins:
        - name: wasm_log
          priority: 7999
          file: t/wasm/log/main.go.wasm
        - name: wasm_log2
          priority: 7998
          file: t/wasm/log/main.go.wasm
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: check schema
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {input = {
                }},
                {input = {
                    conf = {}
                }},
                {input = {
                    conf = ""
                }},
            }) do
                local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    {
                        id = "1",
                        uri = "/echo",
                        upstream = {
                            type = "roundrobin",
                            nodes = {}
                        },
                        plugins = {
                            wasm_log = case.input
                        }
                    }
                )
                ngx.say(json.decode(body).error_msg)
            end
        }
    }
--- response_body
failed to check the configuration of plugin wasm_log err: property "conf" is required
failed to check the configuration of plugin wasm_log err: property "conf" validation failed: wrong type: expected string, got table
failed to check the configuration of plugin wasm_log err: property "conf" validation failed: string too short, expected at least 1, got 0



=== TEST 2: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm_log": {
                            "conf": "blahblah"
                        },
                        "wasm_log2": {
                            "conf": "zzz"
                        }
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
--- response_body
passed



=== TEST 3: hit
--- request
GET /hello
--- grep_error_log eval
qr/run plugin ctx \d+ with conf \S+ in http ctx \d+/
--- grep_error_log_out
run plugin ctx 1 with conf blahblah in http ctx 2
run plugin ctx 1 with conf zzz in http ctx 2



=== TEST 4: run wasm plugin in rewrite phase (prior to the one run in access phase)
--- extra_yaml_config
wasm:
    plugins:
        - name: wasm_log
          priority: 7999
          file: t/wasm/log/main.go.wasm
        - name: wasm_log2
          priority: 7998
          file: t/wasm/log/main.go.wasm
          http_request_phase: rewrite
--- request
GET /hello
--- grep_error_log eval
qr/run plugin ctx \d+ with conf \S+ in http ctx \d+/
--- grep_error_log_out
run plugin ctx 1 with conf zzz in http ctx 2
run plugin ctx 1 with conf blahblah in http ctx 2



=== TEST 5: plugin from service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm_log": {
                            "id": "log",
                            "conf": "blahblah"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "service_id": "1",
                    "hosts": ["foo.com"]
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "service_id": "1",
                    "hosts": ["bar.com"]
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
--- response_body
passed



=== TEST 6: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 4 do
                local host = "foo.com"
                if i % 2 == 0 then
                    host = "bar.com"
                end
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {host = host}})
                if not res then
                    ngx.say(err)
                    return
                end
            end
        }
    }
--- grep_error_log eval
qr/run plugin ctx \d+ with conf \S+ in http ctx \d+/
--- grep_error_log_out
run plugin ctx 1 with conf blahblah in http ctx 2
run plugin ctx 3 with conf blahblah in http ctx 4
run plugin ctx 1 with conf blahblah in http ctx 2
run plugin ctx 3 with conf blahblah in http ctx 4



=== TEST 7: plugin from plugin_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "wasm_log": {
                            "id": "log",
                            "conf": "blahblah"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/hello",
                    "plugin_config_id": "1",
                    "hosts": ["foo.com"]
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/hello",
                    "plugin_config_id": "1",
                    "hosts": ["bar.com"]
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
--- response_body
passed



=== TEST 8: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            for i = 1, 4 do
                local host = "foo.com"
                if i % 2 == 0 then
                    host = "bar.com"
                end
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {host = host}})
                if not res then
                    ngx.say(err)
                    return
                end
            end
        }
    }
--- grep_error_log eval
qr/run plugin ctx \d+ with conf \S+ in http ctx \d+/
--- grep_error_log_out
run plugin ctx 1 with conf blahblah in http ctx 2
run plugin ctx 3 with conf blahblah in http ctx 4
run plugin ctx 1 with conf blahblah in http ctx 2
run plugin ctx 3 with conf blahblah in http ctx 4
