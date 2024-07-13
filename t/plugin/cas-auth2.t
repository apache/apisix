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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: using http should give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "http://a.com",
                cas_callback_uri = "/a/b",
                logout_uri = "/c/d"
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- error_log
risk



=== TEST 2: using https should not give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "https://a.com",
                cas_callback_uri = "/a/b",
                logout_uri = "/c/d"
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- no_error_log
risk
