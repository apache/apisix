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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request && !$block->exec) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11460;

        location / {
            content_by_lua_block {
                require("lib.openapi_to_mcp_fixture").serve()
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: one route per transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-interop-http", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
                { 2, "/mcp-interop-sse", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 2: the official MCP client SDK drives both transports
--- timeout: 300
--- max_size: 2048000
--- exec
cd t && pnpm test --no-color plugin/openapi-to-mcp-interop.spec.ts 2>&1
--- no_error_log
failed to execute the script with status
--- response_body eval
qr/Tests\s+(\d+) passed \(\1\)/



=== TEST 3: remove the extra route so it cannot collide with later suites
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            ngx.say(code < 300 and "deleted" or body)
        }
    }
--- response_body
deleted
