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



=== TEST 2: set up a route with mcp-bridge
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/mcp/*",
                    "plugins": {
                        "mcp-bridge": {
                            "command": "/bin/cat",
                            "base_uri": "/mcp"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { "127.0.0.1:1": 1 }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: message endpoint rejects an unknown sessionId
--- request
POST /mcp/message?sessionId=00000000-0000-4000-8000-000000000000
{"jsonrpc":"2.0","id":1,"method":"tools/list"}
--- more_headers
Content-Type: application/json
--- error_code: 404



=== TEST 4: message endpoint rejects a missing sessionId
--- request
POST /mcp/message
{"jsonrpc":"2.0","id":1,"method":"tools/list"}
--- more_headers
Content-Type: application/json
--- error_code: 404
