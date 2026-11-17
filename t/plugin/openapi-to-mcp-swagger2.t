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
        listen 11470;

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

=== TEST 1: a Swagger 2.0 document produces tools
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-swagger2", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11470",
                    openapi_url = "http://127.0.0.1:11470/swagger2.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 2: parameters carrying their schema inline keep their type
--- request
POST /mcp-swagger2
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
--- response_body_like eval
qr/"petId":\{"type":"integer","format":"int64"\}|"petId":\{"format":"int64","type":"integer"\}/



=== TEST 3: the tool list itself, field by field
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local core = require("apisix.core")
            local function payload(body)
                -- the streamable transport frames the reply as one SSE event
                return require("apisix.core").json.decode(body:match("data: (.-)\n") or body)
            end
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/mcp-swagger2", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json, text/event-stream",
                },
                body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}',
            })
            if not res then ngx.say(err) return end

            local data = payload(res.body)
            local tools = data.result.tools
            for _, tool in ipairs(tools) do
                ngx.say(tool.name)
            end

            -- a body parameter is not turned into an input
            for _, tool in ipairs(tools) do
                if tool.name == "addPetV2" then
                    ngx.say("addPetV2 properties: ",
                            core.json.encode(tool.inputSchema.properties))
                end
            end
        }
    }
--- response_body
GetS2PetNoid
formPetV2
getPetV2
addPetV2
addPetV2 properties: {}



=== TEST 4: calling a 2.0 tool reaches the upstream path
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local core = require("apisix.core")
            local function payload(body)
                -- the streamable transport frames the reply as one SSE event
                return require("apisix.core").json.decode(body:match("data: (.-)\n") or body)
            end
            local httpc = http.new()
            local body = [[{"jsonrpc":"2.0","id":2,"method":"tools/call","params":]] ..
                [[{"name":"getPetV2","arguments":{"pathParameters":{"petId":7},]] ..
                [["queryParameters":{"verbose":false}}}}]]
            local res, err = httpc:request_uri("http://127.0.0.1:1984/mcp-swagger2", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json, text/event-stream",
                },
                body = body,
            })
            if not res then ngx.say(err) return end

            local data = payload(res.body)
            local upstream = core.json.decode(data.result.content[1].text)
            -- basePath is not prepended: the upstream is base_url, and the
            -- path comes from the document key alone
            ngx.say(upstream.data.seen_method, " ", upstream.data.seen_path)
        }
    }
--- response_body
GET /s2/pet/7?verbose=false



=== TEST 5: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned
