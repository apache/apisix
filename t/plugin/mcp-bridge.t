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
                {command = "npx"},
                {},
                {command = 123},
                {command = "npx", args = { "-y", "test" }},
                {command = "npx", args = "test"},
            }
            local plugin = require("apisix.plugins.mcp-bridge")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "command" is required
property "command" validation failed: wrong type: expected string, got number
done
property "args" validation failed: wrong type: expected array, got string



=== TEST 2: message endpoint only accepts sessions with a live SSE connection
--- config
    location /t {
        content_by_lua_block {
            local server = require("apisix.plugins.mcp.server")
            local broker = require("apisix.plugins.mcp.broker.shared_dict")

            -- a missing or unknown session id is not accepted
            ngx.say("nil: ", server.session_exists(nil))
            ngx.say("unknown: ", server.session_exists("bogus"))

            -- a registered session is visible to the message endpoint
            local b = broker.new({ session_id = "sess-a" })
            b:register()
            ngx.say("registered: ", server.session_exists("sess-a"))

            -- teardown removes it again
            b:unregister()
            ngx.say("after teardown: ", server.session_exists("sess-a"))
        }
    }
--- response_body
nil: false
unknown: false
registered: true
after teardown: false



=== TEST 3: per-session queue is bounded
--- config
    location /t {
        content_by_lua_block {
            local broker = require("apisix.plugins.mcp.broker.shared_dict")
            local b = broker.new({ session_id = "sess-q" })

            local ok, err
            for _ = 1, 1024 do
                ok, err = b:push("m")
            end
            ngx.say("at_cap ok=", tostring(ok), " err=", tostring(err))

            ok, err = b:push("m")
            ngx.say("over_cap ok=", tostring(ok), " err=", tostring(err))

            b:unregister()
        }
    }
--- response_body
at_cap ok=true err=nil
over_cap ok=nil err=queue is full
