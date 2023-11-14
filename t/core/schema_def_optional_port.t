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

repeat_each(2);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Sanity check node_schema optional port
--- config
    location /t {
        content_by_lua_block {
            local schema_def = require("apisix.schema_def")
            local core = require("apisix.core")


            upstream = {
                nodes = {
                    {host= "127.0.0.1", weight= 1},
                },
                type = "roundrobin",
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil)


            upstream = {
                nodes = {
                    {host= "127.0.0.1", weight= 2, port= 8080},
                },
                type = "roundrobin",
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil)


            upstream = {
                nodes = {
                    {host= "127.0.0.1", weight= 1},
                    {host= "127.0.0.1", weight= 2},
                    {host= "127.0.0.1", weight= 2, port= 8080},
                    {host= "127.0.0.1", weight= 2, port= 8081},
                },
                type = "roundrobin",
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
