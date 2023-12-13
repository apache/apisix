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

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: parse_time_unit
--- config
    location /t {
        content_by_lua_block {
            local parse_time_unit = require("apisix.core.config_util").parse_time_unit
            for _, case in ipairs({
                {exp = 1, input = "1"},
                {exp = 1, input = "1s"},
                {exp = 60, input = "60s"},
                {exp = 1.1, input = "1s100ms"},
                {exp = 10.001, input = "10s1ms"},
                {exp = 3600, input = "60m"},
                {exp = 3600.11, input = "60m110ms"},
                {exp = 3710, input = "1h110"},
                {exp = 5400, input = "1h  30m"},
                {exp = 34822861.001, input = "1y1M1w1d1h1m1s1ms"},
            }) do
                assert(case.exp == parse_time_unit(case.input),
                       string.format("input %s, got %s", case.input,
                            parse_time_unit(case.input)))
            end

            for _, case in ipairs({
                {exp = "invalid data: -", input = "-1"},
                {exp = "unexpected unit: h", input = "1m1h"},
                {exp = "invalid data: ", input = ""},
                {exp = "specific unit conflicts with the default unit second", input = "1s1"},
            }) do
                local _, err = parse_time_unit(case.input)
                assert(case.exp == err,
                       string.format("input %s, got %s", case.input, err))
            end
        }
    }



=== TEST 2: add_clean_handler / cancel_clean_handler / fire_all_clean_handlers
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.core.config_util")
            local function setup()
                local item = {clean_handlers = {}}
                local idx1 = util.add_clean_handler(item, function()
                    ngx.log(ngx.WARN, "fire one")
                end)
                local idx2 = util.add_clean_handler(item, function()
                    ngx.log(ngx.WARN, "fire two")
                end)
                return item, idx1, idx2
            end

            local function setup_to_false()
                local item = false
                return item
            end

            local item, idx1, idx2 = setup()
            util.cancel_clean_handler(item, idx1, true)
            util.cancel_clean_handler(item, idx2, true)

            local item, idx1, idx2 = setup()
            util.fire_all_clean_handlers(item)

            local item, idx1, idx2 = setup()
            util.cancel_clean_handler(item, idx2)
            util.fire_all_clean_handlers(item)

            local item, idx1, idx2 = setup()
            util.cancel_clean_handler(item, idx1)
            util.fire_all_clean_handlers(item)

            local item = setup_to_false()
            util.fire_all_clean_handlers(item)
        }
    }
--- grep_error_log eval
qr/fire \w+/
--- grep_error_log_out eval
"fire one\nfire two\n" x 3
