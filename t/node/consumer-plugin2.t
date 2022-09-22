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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->response_body) {
        $block->set_value("response_body", "passed\n");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});


our $debug_config = t::APISIX::read_file("conf/debug.yaml");
$debug_config =~ s/basic:\n  enable: false/basic:\n  enable: true/;
$debug_config =~ s/hook_conf:\n  enable: false/hook_conf:\n  enable: true/;

run_tests;

__DATA__

=== TEST 1: use the latest consumer modifiedIndex as lrucache key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        },
                        "basic-auth": {}
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
                    "plugin_config_id": "1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello"]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhcg=="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.print(res.body)

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1", "127.0.0.1"]
                        },
                        "basic-auth": {}
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local res, err = httpc:request_uri(uri, {headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bala"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhbGE="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
{"message":"Your IP address is not allowed"}
hello world
hello world
