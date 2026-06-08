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



=== TEST 2: max_sessions schema validation
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {command = "npx", max_sessions = 10},
                {command = "npx", max_sessions = 0},
                {command = "npx", max_sessions = "10"},
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
property "max_sessions" validation failed: expected 0 to be at least 1
property "max_sessions" validation failed: wrong type: expected integer, got string



=== TEST 3: session limit acquire/release bookkeeping
--- config
    location /t {
        content_by_lua_block {
            local session_limit = require("apisix.plugins.mcp.session_limit")

            -- two slots available
            ngx.say(session_limit.acquire(2)) -- true
            ngx.say(session_limit.acquire(2)) -- true
            ngx.say(session_limit.count())    -- 2
            ngx.say(session_limit.acquire(2)) -- false, ceiling reached

            -- releasing frees a slot for the next session
            session_limit.release()
            ngx.say(session_limit.count())    -- 1
            ngx.say(session_limit.acquire(2)) -- true again

            -- release never drops below zero
            session_limit.release()
            session_limit.release()
            session_limit.release()
            ngx.say(session_limit.count())    -- 0

            -- a missing or non-numeric ceiling fails closed instead of raising
            ngx.say(session_limit.acquire(nil))   -- false
            ngx.say(session_limit.acquire("2"))   -- false
            ngx.say(session_limit.count())        -- 0
        }
    }
--- response_body
true
true
2
false
1
true
0
false
false
0



=== TEST 4: SSE endpoint rejects new sessions once the ceiling is reached
--- config
    location /t {
        content_by_lua_block {
            local wrapper = require("apisix.plugins.mcp.server_wrapper")
            local session_limit = require("apisix.plugins.mcp.session_limit")

            -- occupy the single available slot so the next session is over the
            -- ceiling and must be rejected by the handler
            session_limit.acquire(1)

            local conf = { base_uri = "", max_sessions = 1 }
            local ctx = { var = { uri = "/sse" } }
            wrapper.access(conf, ctx, { event_handler = {} })
        }
    }
--- error_code: 429
--- response_body
{"error_msg":"too many concurrent MCP sessions"}
