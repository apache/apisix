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

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body, res = t.test('/v1/schema',
                ngx.HTTP_GET,
                nil,
                [[{
                    "main": {
                        "consumer": {"type":"object"},
                        "global_rule": {"type":"object"},
                        "plugins": {"type":"array"},
                        "proto": {"type":"object"},
                        "route": {"type":"object"},
                        "service": {"type":"object"},
                        "ssl": {"type":"object"},
                        "stream_route": {"type":"object"},
                        "upstream": {"type":"object"}
                    },
                    "plugins": {
                        "example-plugin": {
                            "version": 0.1,
                            "priority": 0,
                            "schema": {"type":"object"},
                            "metadata_schema": {"type":"object"}
                        },
                        "mqtt-proxy": {
                            "schema": {"type":"object"},
                            "priority": 1000
                        },
                        "basic-auth": {
                            "type": "auth",
                            "consumer_schema": {"type":"object"}
                        }
                    }
                }]]
                )
            ngx.satus = code
            ngx.say(body)
        }
    }
--- response_body
passed
