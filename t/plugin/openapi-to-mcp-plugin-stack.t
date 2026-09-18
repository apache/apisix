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
# A route running openapi-to-mcp is still an ordinary route: the plugins
# configured alongside it have to keep working. This covers the ones above it in
# the access chain (key-auth at 2500, limit-count at 1002) and the response
# filters that see a response the gateway produced itself rather than proxied.
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
        listen 11500;

        location /openapi.json {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.header["Content-Type"] = "application/json"
                ngx.say(core.json.encode({
                    openapi = "3.0.0",
                    info = { title = "Demo", version = "1.0.0" },
                    paths = { ["/pet/{petId}"] = { get = {
                        operationId = "getPet",
                        parameters = {
                            { name = "petId", ["in"] = "path", required = true,
                              schema = { type = "integer" } },
                        },
                    } } },
                }))
            }
        }

        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.header["Content-Type"] = "application/json"
                ngx.say(core.json.encode({ seen_path = ngx.var.request_uri }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: a consumer for the auth plugin above openapi-to-mcp
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT, [[{
                "username": "stackuser",
                "plugins": { "key-auth": { "key": "stack-key" } }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: key-auth, limit-count and response-rewrite stacked on one route
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-stack", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11500",
                    openapi_url = "http://127.0.0.1:11500/openapi.json",
                }, {
                    ["key-auth"] = {},
                    ["limit-count"] = {
                        count = 2,
                        time_window = 60,
                        rejected_code = 429,
                        key = "remote_addr",
                    },
                    ["response-rewrite"] = { headers = { add = { "X-Mcp-Stack: seen" } } },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 3: without a key the auth plugin answers, not the MCP server
--- request
POST /mcp-stack
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
--- error_code: 401
--- response_body
{"message":"Missing API key in request"}



=== TEST 4: with a key the MCP server answers, through the response filters
--- request
POST /mcp-stack
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: stack-key
--- response_body_like
.*"name":"getPet".*
--- response_headers
X-Mcp-Stack: seen
X-RateLimit-Remaining: 1



=== TEST 5: limit-count counts MCP requests and cuts the third one off
--- pipelined_requests eval
["POST /mcp-stack\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
 "POST /mcp-stack\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}",
 "POST /mcp-stack\n{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"ping\"}"]
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: stack-key
--- error_code eval
[200, 200, 429]



=== TEST 6: the same stack in front of an SSE route
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 2, "/mcp-stack-sse", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11500",
                    openapi_url = "http://127.0.0.1:11500/openapi.json",
                }, {
                    ["key-auth"] = {},
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 7: an unauthenticated stream is refused before it opens
--- request
GET /mcp-stack-sse
--- more_headers
Accept: text/event-stream
--- error_code: 401



=== TEST 8: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/stackuser', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned
