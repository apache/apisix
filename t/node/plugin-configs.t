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
log_level('info');
no_root_location();
no_shuffle();
master_on();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: change plugin config will cause the conf_version change
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, err = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "hello"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugin_config_id": 1,
                    "plugins": {
                        "example-plugin": {
                            "i": 1
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local code, err, org_body = t('/hello')
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(org_body)

            local code, err = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PATCH,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "world"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local code, err, org_body = t('/hello')
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(org_body)
        }
    }
--- response_body
hello
world
--- grep_error_log eval
qr/conf_version: \d+#\d/
--- grep_error_log_out eval
qr/conf_version: \d+#1
conf_version: \d+#2
/



=== TEST 2: validated plugins configuration via incremental sync
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local core = require("apisix.core")

            assert(core.etcd.set("/plugin_configs/1",
                {id = 1, plugins = { ["uri-blocker"] = { block_rules =  {"root.exe","root.m+"} }}}
            ))
            -- wait for sync
            ngx.sleep(0.6)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello?x=root.exe"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.status = res.status
            ngx.say(uri)
            ngx.say(res.body)

        }
    }
--- request
GET /t
--- error_code: 403



=== TEST 3: validated plugins configuration via incremental sync (malformed data)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local core = require("apisix.core")

            assert(core.etcd.set("/plugin_configs/1",
                {id = 1, plugins = { ["uri-blocker"] = { block_rules =  1 }}}
            ))
            -- wait for sync
            ngx.sleep(0.6)
        }
    }
--- request
GET /t
--- error_log
property "block_rules" validation failed
