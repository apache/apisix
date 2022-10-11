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

=== TEST 1: sanity (bearer_only = true)
--- config
    location /t {
        content_by_lua_block {
            local case = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = true}
            local ok, err = require("apisix.plugins.openid-connect").check_schema(case)
            assert(not case.session, "not expect session was generated")
        }
    }



=== TEST 2: sanity (bearer_only = false)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local case = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false}
            local ok, err = require("apisix.plugins.openid-connect").check_schema(case)
            assert(ok and case.session and case.session.secret, "no session secret generated")
        }
    }



=== TEST 3: sanity (bearer_only = false, user-set secret)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local case = {client_id = "a", client_secret = "b", discovery = "c", bearer_only = false, session = {secret = "test"}}
            local ok, err = require("apisix.plugins.openid-connect").check_schema(case)
            assert(ok and case.session and case.session.secret and case.session.secret == "test", "user-set secret is incorrect")
        }
    }
