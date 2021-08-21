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

=== TEST 1: setenv
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            core.os.setenv("TEST", "A")
            ngx.say(os.getenv("TEST"))
            core.os.setenv("TEST", 1)
            ngx.say(os.getenv("TEST"))
        }
    }
--- response_body
A
1



=== TEST 2: setenv, bad arguments
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            for _, c in ipairs({
                {name = "A"},
                {value = "A"},
                {name = 1, value = "A"},
            }) do
                local ok = core.os.setenv(c.name, c.value)
                ngx.say(ok)
            end
        }
    }
--- response_body
false
false
false
