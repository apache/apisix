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



=== TEST 2: setup route (mcp filesystem)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "mcp-bridge": {
                                "base_uri": "/mcp",
                                "command": "npx",
                                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/"]
                            }
                        },
                        "uri": "/mcp/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: test mcp client
--- timeout: 20
--- exec
cd t/plugin/mcp && pnpm test 2>&1
--- no_error_log
failed to execute the script with status
--- response_body eval
qr/PASS .\/bridge.spec.ts/
