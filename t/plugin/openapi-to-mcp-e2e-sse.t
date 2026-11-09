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



=== TEST 5: the same route with the variable written without braces
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                    -- resolve_var takes this form too, so the stream has to
                    -- freeze what it resolved here as well
                    headers = { Authorization = "Bearer $http_x_user" },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 6: a brace-less variable is frozen just the same
--- exec
python3 t/plugin/openapi_to_mcp_sse_frozen_vars.py /mcp 2>&1
--- response_body
post status: 202
upstream saw: Bearer alice



=== TEST 7: a route whose configuration holds no variable
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



=== TEST 8: its session record keeps no copy of the resolved headers
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local dict = ngx.shared["mcp-session"]

            -- what handle_get stores when nothing needs re-resolving
            local plain = assert(session.create("route-1"))
            ngx.say("plain context: ", tostring(session.context(plain)))

            -- and what it stores when the configuration holds a variable
            local frozen = assert(session.create("route-1",
                                  { headers = { Authorization = "Bearer t" } }))
            ngx.say("frozen context: ", session.context(frozen).headers.Authorization)
            ngx.say("in the dict: ",
                    tostring(string.find(tostring(dict:get("openapi-to-mcp:" .. plain .. ":alive")),
                                         "Bearer", 1, true) ~= nil))
        }
    }
--- response_body
plain context: nil
frozen context: Bearer t
in the dict: false



=== TEST 9: two sse routes, one of them without authentication
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
                { 2, "/mcp-other", {
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



=== TEST 10: a session issued by one route is not accepted by another
--- timeout: 30
--- exec
python3 t/plugin/openapi_to_mcp_cross_route.py /mcp /mcp-other 2>&1
--- response_body
own route: 202
other route: 404
pushed on own stream: True



=== TEST 11: clean up the extra route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned



=== TEST 12: an sse route that names the origins it expects
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                    allowed_origins = { "https://app.example.com" },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 13: the stream is refused from another origin
--- request
GET /mcp
--- more_headers
Origin: https://evil.example.com
--- error_code: 403
--- response_body
{"message":"Origin not allowed. Add it to allowed_origins on this route to accept it."}
--- error_log
rejected an MCP request with a disallowed Origin



=== TEST 14: an sse route that names no origins at all
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



=== TEST 15: with nothing to check it against, the stream is refused
--- request
GET /mcp
--- more_headers
Origin: https://evil.example.com
--- error_code: 403
--- response_body
{"message":"Origin not allowed. Add it to allowed_origins on this route to accept it."}
--- error_log
nothing to check it against



=== TEST 16: loopback at both ends opens a stream
--- exec
timeout 3 curl -sSN -H "Origin: http://localhost:1984" http://localhost:1984/mcp 2>&1 | head -1
--- response_body
event: endpoint



=== TEST 17: a non-browser client, which sends no Origin, still opens a stream
--- exec
timeout 3 curl -sSN http://localhost:1984/mcp 2>&1 | head -1
--- response_body
event: endpoint



=== TEST 18: a rebound name is refused on the stream too
--- exec
timeout 5 curl -sSN -o /dev/null -w "%{http_code}\n" http://localhost:1984/mcp \
    -H "Host: attacker.example" \
    -H "Origin: http://attacker.example" 2>&1
--- response_body
403
--- error_log
nothing to check it against



=== TEST 19: an sse route matched on a wildcard host
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                }, nil, { hosts = { "*.example.com" } } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 20: the wildcard routes the stream request but does not vouch for it
--- exec
timeout 5 curl -sSN -o /dev/null -w "%{http_code}\n" http://localhost:1984/mcp \
    -H "Host: attacker.example.com" \
    -H "Origin: http://attacker.example.com" 2>&1
--- response_body
403
--- error_log
nothing to check it against
