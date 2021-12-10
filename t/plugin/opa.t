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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity check with minimal valid configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.opa")
            local ok, err = plugin.check_schema({host = "http://127.0.0.1:8181", policy = "example/allow"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: missing `policy`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.opa")
            local ok, err = plugin.check_schema({host = "http://127.0.0.1:8181"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "policy" is required



=== TEST 3: wrong type for `host`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.opa")
            local ok, err = plugin.check_schema({host = 3233, policy = "example/allow"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "host" validation failed: wrong type: expected string, got number



=== TEST 4: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:8181",
                                "policy": "example/allow"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: hit route (with wrong header request)
--- request
GET /hello
--- more_headers
test-header: not-for-test
--- error_code: 403



=== TEST 6: hit route (with correct request)
--- request
GET /hello
--- more_headers
test-header: only-for-test
--- response_body
hello world
