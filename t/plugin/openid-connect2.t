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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {
                    name = "sanity (bearer_only = true)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = true},
                    cb = function(ok, err, case)
                        assert(ok and not case.session, "not expect session was generated")
                    end,
                },
                {
                    name = "sanity (bearer_only = false)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false},
                    cb = function(ok, err, case)
                        assert(ok and case.session and case.session.secret, "no session secret generated")
                    end,
                },
                {
                    name = "sanity (bearer_only = false, user-set secret, less than 16 characters)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false, session = {secret = "test"}},
                    cb = function(ok, err, case)
                        assert(not ok and err == "property \"session\" validation failed: property \"secret\" validation failed: string too short, expected at least 16, got 4", "too short key passes validation")
                    end,
                },
                {
                    name = "sanity (bearer_only = false, user-set secret, more than 16 characters)",
                    data = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false, session = {secret = "test_secret_more_than_16"}},
                    cb = function(ok, err, case)
                        assert(ok and case.session and case.session.secret and case.session.secret == "test_secret_more_than_16", "user-set secret is incorrect")
                    end,
                },
            }

            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case.data)
                case.cb(ok, err, case.data)
            end
        }
    }
