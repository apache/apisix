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

=== TEST 1: empty userinfo claims survive the session round-trip as arrays
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local session_utils = require("resty.session.utils")

            -- openid-connect stores the userinfo table in the session and reads it
            -- back on later requests before encoding it into X-Userinfo. An empty
            -- claim such as "roles" must survive that round-trip as an array; if the
            -- session library decodes it without the array metatable, X-Userinfo
            -- ends up carrying `"roles":{}` instead of `"roles":[]`.
            local userinfo = core.json.decode('{"sub":"a UID","name":"Testuser One","roles":[]}')

            local stored = session_utils.encode_json(userinfo)
            local restored = session_utils.decode_json(stored)

            ngx.say(stored:find('"roles":%[%]', 1) and "stored as array" or "stored as object")
            ngx.say(core.json.encode(restored.roles))
        }
    }
--- response_body
stored as array
[]
