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
# mcp-tools-acl narrows what an authenticated client may do over an MCP
# conversation openapi-to-mcp is serving: it refuses a tools/call for a tool the
# matched rule does not allow, and removes those tools from the tools/list
# answer so a client never learns they exist.
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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.mcp-tools-acl")
            local ok, err = plugin.check_schema({
                rules = {
                    { allow_tools = {"getPetById"}, expr = {{"consumer_name", "==", "alice"}} },
                    { deny_tools = {"deletePet"}, rejected_code = 401,
                      rejected_msg = "no" },
                },
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: rules is required
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.mcp-tools-acl")
            local ok, err = plugin.check_schema({})
            ngx.say(err)
        }
    }
--- response_body
property "rules" is required



=== TEST 3: a malformed expr is rejected by check_schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.mcp-tools-acl")
            local ok, err = plugin.check_schema({
                rules = {{ allow_tools = {"getPetById"},
                           expr = {{"consumer_name", "!!!", "alice"}} }},
            })
            ngx.say(ok, " ", err)
        }
    }
--- response_body_like
^false failed to validate the 'expr' expression: .*



=== TEST 4: two consumers, so a rule can pick between them
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, c in ipairs({{"alice", "alice-key"}, {"bob", "bob-key"}}) do
                local code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT,
                    string.format(
                        [[{"username":"%s","plugins":{"key-auth":{"key":"%s"}}}]],
                        c[1], c[2]))
                if code >= 300 then
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 5: a route that denies deletePet to everyone who authenticates
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-acl", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["key-auth"] = {},
                    ["mcp-tools-acl"] = {
                        rules = {{
                            deny_tools = { "deletePet" },
                            rejected_code = 403,
                            rejected_msg = "deletePet is not allowed",
                        }},
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 6: a denied tools/call never reaches the MCP server
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"deletePet","arguments":{"petId":1}}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 403
--- response_body
{"message":"deletePet is not allowed"}



=== TEST 7: a tool the rule says nothing about is called as usual
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPetById","arguments":{"pathParameters":{"petId":1}}}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 200
--- response_body_like
.*seen_path.*



=== TEST 8: the denied tool is gone from tools/list as well
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 200
--- response_body_like
.*"name":"getPetById".*
--- response_body_unlike
.*"name":"deletePet".*



=== TEST 9: an allow list leaves only what it names
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-acl", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["key-auth"] = {},
                    ["mcp-tools-acl"] = {
                        rules = {{ allow_tools = { "getPetById" } }},
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 10: a tool outside the allow list is refused with the default code
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"addPet","arguments":{}}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 403
--- response_body
{"message":"MCP tool is not allowed"}



=== TEST 11: tools/list keeps only the allowed tool
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 200
--- response_body_like
.*"name":"getPetById".*
--- response_body_unlike
.*"name":"addPet".*



=== TEST 12: expr picks a different rule per consumer
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-acl", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["key-auth"] = {},
                    ["mcp-tools-acl"] = {
                        rules = {
                            { expr = {{"consumer_name", "==", "alice"}},
                              allow_tools = { "getPetById" } },
                            { expr = {{"consumer_name", "==", "bob"}},
                              allow_tools = { "addPet" } },
                        },
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 13: alice may call getPetById, bob may not
--- pipelined_requests eval
["POST /mcp-acl\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"getPetById\",\"arguments\":{\"pathParameters\":{\"petId\":1}}}}",
 "POST /mcp-acl\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"addPet\",\"arguments\":{}}}"]
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code eval
[200, 403]



=== TEST 14: and the other way round for bob
--- pipelined_requests eval
["POST /mcp-acl\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"getPetById\",\"arguments\":{\"pathParameters\":{\"petId\":1}}}}",
 "POST /mcp-acl\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"addPet\",\"arguments\":{}}}"]
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: bob-key
--- error_code eval
[403, 200]



=== TEST 15: no rule matches, so nothing is enforced
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-acl", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["key-auth"] = {},
                    ["mcp-tools-acl"] = {
                        rules = {{ expr = {{"consumer_name", "==", "nobody"}},
                                   allow_tools = { "getPetById" } }},
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 16: a tool no rule covers goes through
--- request
POST /mcp-acl
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"addPet","arguments":{}}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
apikey: alice-key
--- error_code: 200



=== TEST 17: without a consumer the ACL has nobody to police
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 2, "/mcp-acl-anon", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["mcp-tools-acl"] = {
                        rules = {{ deny_tools = { "deletePet" } }},
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 18: so the denied tool is callable on that route
--- request
POST /mcp-acl-anon
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"deletePet","arguments":{"petId":1}}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
--- error_code: 200



=== TEST 19: a route without openapi-to-mcp is not an MCP conversation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3', ngx.HTTP_PUT, [[{
                "uri": "/no-mcp",
                "plugins": {
                    "key-auth": {},
                    "mcp-tools-acl": {
                        "rules": [{"deny_tools": ["deletePet"]}]
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:11460": 1},
                    "type": "roundrobin"
                }
            }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: so the plugin stands aside and says why
--- request
POST /no-mcp
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"deletePet","arguments":{"petId":1}}}
--- more_headers
Content-Type: application/json
apikey: alice-key
--- error_code: 200
--- error_log
openapi-to-mcp plugin is not active on this route



=== TEST 21: the same filtering over the SSE transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 4, "/mcp-acl-sse", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                }, {
                    ["key-auth"] = {},
                    ["mcp-tools-acl"] = {
                        rules = {{ allow_tools = { "getPetById" } }},
                    },
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 22: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, id in ipairs({1, 2, 3, 4}) do
                t('/apisix/admin/routes/' .. id, ngx.HTTP_DELETE)
            end
            t('/apisix/admin/consumers/alice', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/bob', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned
