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

=== TEST 1: route with the sse transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
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



=== TEST 2: full SSE round trip served in-process
--- exec
python3 t/plugin/openapi_to_mcp_sse_roundtrip.py /mcp 2>&1
--- response_body
endpoint path: /mcp
has sessionId: True
post status: 202
protocolVersion: 2024-11-05
serverInfo: openapi2mcp-sse 0.0.1
unknown session status: 404



=== TEST 3: an sse route whose header carries a request variable
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                    headers = { Authorization = "Bearer ${http_x_user}" },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 4: the value resolved when the stream opened is the one used
--- exec
python3 t/plugin/openapi_to_mcp_sse_frozen_vars.py /mcp 2>&1
--- response_body
post status: 202
upstream saw: Bearer alice



=== TEST 5: a route whose configuration holds no variable
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "fixed-credential" },
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 6: its session record keeps no copy of the resolved headers
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local dict = ngx.shared["mcp-session"]

            -- what handle_get stores when nothing needs re-resolving
            local plain = assert(session.create(nil))
            ngx.say("plain context: ", tostring(session.context(plain)))

            -- and what it stores when the configuration holds a variable
            local frozen = assert(session.create({ headers = { Authorization = "Bearer t" } }))
            ngx.say("frozen context: ", session.context(frozen).headers.Authorization)
            ngx.say("in the dict: ",
                    tostring(string.find(tostring(dict:get(plain .. ":alive")),
                                         "Bearer", 1, true) ~= nil))
        }
    }
--- response_body
plain context: nil
frozen context: Bearer t
in the dict: false
