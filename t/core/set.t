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

    $block->set_value("no_error_log", "[error]");
    $block->set_value("request", "GET /t");

    $block;
});

run_tests;

__DATA__

=== TEST 1: eq
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local cases = {
                {expect = true, a = {}, b = {}},
                {expect = true, a = {a = 1}, b = {a = 1}},
                {expect = true, a = {a = 1}, b = {a = 2}},
                {expect = false, a = {b = 1}, b = {a = 1}},
                {expect = false, a = {a = 1, b = 1}, b = {a = 1}},
                {expect = false, a = {a = 1}, b = {a = 1, b = 2}},
            }
            for _, t in ipairs(cases) do
                local actual = core.set.eq(t.a, t.b)
                local expect = t.expect
                if actual ~= expect then
                    ngx.say("expect ", expect, ", actual ", actual)
                    return
                end
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
