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

=== TEST 1: key.build is deterministic for identical bodies
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello" }} })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
SAME



=== TEST 2: changing the model changes the key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o",      messages = {{ role = "user", content = "hello" }} })
            local b = key.build({ model = "gpt-4o-mini", messages = {{ role = "user", content = "hello" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 3: changing message content changes the key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "hello"   }} })
            local b = key.build({ model = "gpt-4o", messages = {{ role = "user", content = "goodbye" }} })
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 4: message-array order matters (turn-order is semantic)
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local a = key.build({ model = "gpt-4o", messages = {
                { role = "user",      content = "A" },
                { role = "assistant", content = "B" },
            }})
            local b = key.build({ model = "gpt-4o", messages = {
                { role = "assistant", content = "B" },
                { role = "user",      content = "A" },
            }})
            ngx.say(a == b and "SAME" or "diff")
        }
    }
--- response_body
diff



=== TEST 5: identical bodies built in different declaration orders share a key
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            -- Build the same logical body two different ways. dkjson
            -- sorts object keys so the canonical encoding is identical.
            local a = key.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "hi" }},
            })
            local b = key.build({
                messages = {{ content = "hi", role = "user" }},
                model    = "gpt-4o",
            })
            ngx.say(a == b and "ok" or "MISMATCH")
        }
    }
--- response_body
ok
