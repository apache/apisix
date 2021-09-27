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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: trigger full gc
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local before = collectgarbage("count")
            do
                local tab = {}
                for i = 1, 10000 do
                    tab[i] = {"a", 1}
                end
            end
            local after_alloc = collectgarbage("count")
            local code = t.test('/v1/gc',
                ngx.HTTP_POST
            )
            local after_gc = collectgarbage("count")
            if code == 200 then
                if after_alloc - after_gc > 0.9 * (after_alloc - before) then
                    ngx.say("ok")
                else
                    ngx.say(before, " ", after_alloc, " ", after_gc)
                end
            end
        }
    }
--- response_body
ok
