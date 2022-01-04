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

=== TEST 1: validate allow_origins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cors")
            local function validate(val)
                local conf = {}
                conf.allow_origins = val
                return plugin.check_schema(conf)
            end

            local good = {
                "*",
                "**",
                "null",
                "http://y.com.uk",
                "https://x.com",
                "https://x.com,http://y.com.uk",
                "https://x.com,http://y.com.uk,http://c.tv",
                "https://x.com,http://y.com.uk:12000,http://c.tv",
            }
            for _, g in ipairs(good) do
                local ok, err = validate(g)
                if not ok then
                    ngx.say("failed to validate ", g, ", ", err)
                end
            end

            local bad = {
                "",
                "*a",
                "*,http://y.com",
                "nulll",
                "http//y.com.uk",
                "x.com",
                "https://x.com,y.com.uk",
                "https://x.com,*,https://y.com.uk",
                "https://x.com,http://y.com.uk,http:c.tv",
            }
            for _, b in ipairs(bad) do
                local ok, err = validate(b)
                if ok then
                    ngx.say("failed to reject ", b)
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done
