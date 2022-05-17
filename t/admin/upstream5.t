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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set upstream(kafka scheme)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka"
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: set upstream(empty tls)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka",
                "tls": {}
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: set upstream(tls without verify)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test("/apisix/admin/upstreams/kafka", ngx.HTTP_PUT, [[{
                "nodes": {
                    "127.0.0.1:9092": 1
                },
                "type": "none",
                "scheme": "kafka",
                "tls": {
                    "verify": false
                }
            }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
