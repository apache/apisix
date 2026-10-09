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

=== TEST 1: route with the streamable_http transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    headers = { Authorization = "test-api-key" },
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 2: initialize is answered in-process
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' "
r = d['result']
print(r['protocolVersion'])
print(r['serverInfo']['name'], r['serverInfo']['version'])
print(json.dumps(r['capabilities']['tools']))
"
--- response_body
2025-03-26
openapi2mcp 0.0.1
{}



=== TEST 3: an unknown protocol version falls back to the latest
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' "
print(d['result']['protocolVersion'])
"
--- response_body
2025-11-25



=== TEST 4: tools/list returns the generated tool
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' "
t = d['result']['tools'][0]
print(t['name'], '|', t['description'])
print(sorted(t['inputSchema']['properties'].keys()))
"
--- response_body
getPet | Get a pet
['pathParameters', 'queryParameters']



=== TEST 5: the generated inputSchema carries no $schema or additionalProperties
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' "
schema = d['result']['tools'][0]['inputSchema']
print('\$schema' in schema)
print('additionalProperties' in schema)
"
--- response_body
False
False



=== TEST 6: tools/call reaches the upstream with path, query default and conf header
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"getPet","arguments":{"pathParameters":{"petId":7}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['status'])
print(inner['data']['seen_path'])
print(inner['data']['seen_method'])
print(inner['data']['seen_auth'])
"
--- response_body
200
/pet/7?verbose=true
GET
test-api-key



=== TEST 7: ping
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":9,"method":"ping"}' "
print(json.dumps(d['result']), d['id'])
"
--- response_body
{} 9



=== TEST 8: a notification is accepted with 202 and no body
--- exec
timeout 5 curl -X POST -sS -o /dev/null -w '%{http_code}' http://localhost:1984/mcp \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" 2>&1 | cat
--- response_body chomp
202



=== TEST 9: an unknown method is a JSON-RPC method-not-found error
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":8,"method":"resources/list","params":{}}' "
print(d['error']['code'], d['error']['message'])
"
--- response_body
-32601 Method not found



=== TEST 10: an Accept header missing text/event-stream gets 406
--- exec
timeout 5 curl -X POST -sS -o /dev/null -w '%{http_code}' http://localhost:1984/mcp \
    -d '{"jsonrpc":"2.0","id":1,"method":"ping"}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" 2>&1 | cat
--- response_body chomp
406



=== TEST 11: calling an unknown tool sets isError instead of a JSON-RPC error
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope","arguments":{}}}' "
print(d['result']['isError'])
print(d['result']['content'][0]['text'])
"
--- response_body
True
MCP error -32602: Tool nope not found



=== TEST 12: a malformed JSON-RPC message is rejected with a null-id parse error
--- exec
timeout 5 curl -X POST -sS -o /dev/null -w '%{http_code}' http://localhost:1984/mcp \
    -d '{"jsonrpc":"1.0","id":5,"method":"ping"}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" 2>&1 | cat
--- response_body chomp
400



=== TEST 13: the parse error reports a null id even when the request had one
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":6,"method":"ping","params":"notatable"}' "
print(d['error']['code'], '|', d['error']['message'])
print(d['id'] is None)
"
--- response_body
-32700 | Parse error: Invalid JSON-RPC message
True



=== TEST 14: object and array query parameters with the default style
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    flatten_parameters = true,
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/objq.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 15: form style with explode, the OpenAPI default, repeats arrays and spreads objects
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"objQuery","arguments":{"filter":{"a":"x"},"tags":["t1","t2"]}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_path'])
"
--- response_body
/q?a=x&tags=t1&tags=t2



=== TEST 16: a route over a document using every query style
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    flatten_parameters = true,
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/styles.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 17: each query parameter is serialized by its declared style and explode
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"styles","arguments":{"formArr":["a","b c"],"spaceArr":["a","b"],"pipeArr":["a","b"],"deep":{"x":"1"},"formObj":{"k":"v"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_path'])
"
--- response_body
/s?deep%5Bx%5D=1&formArr=a,b%20c&formObj=k,v&pipeArr=a|b&spaceArr=a%20b



=== TEST 18: a route over a document with Path Item parameters
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/pathitem.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 19: Path Item parameters reach the tool, and the operation's override wins
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' "
props = d['result']['tools'][0]['inputSchema']['properties']
print(props['pathParameters']['properties']['id']['type'], props['pathParameters']['required'])
print(props['queryParameters']['properties']['verbose']['type'])
"
--- response_body
integer ['id']
string



=== TEST 20: a call fills the inherited path parameter
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPetById","arguments":{"pathParameters":{"id":5},"queryParameters":{"verbose":"yes"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_path'])
"
--- response_body
/pets/5?verbose=yes



=== TEST 21: a route over a document whose request body is text/plain
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/textbody.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 22: the request body is sent with the media type the operation declares
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"addNote","arguments":{"requestBody":"hello"}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_method'], inner['data']['seen_content_type'], inner['data']['seen_body'])
"
--- response_body
POST text/plain hello



=== TEST 23: a Content-Type configured on the route is not overridden
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { ["content-type"] = "text/markdown" },
                    openapi_url = "http://127.0.0.1:11460/textbody.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 24: the configured media type is what the API receives
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"addNote","arguments":{"requestBody":"hello"}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_content_type'], inner['data']['seen_body'])
"
--- response_body
text/markdown hello



=== TEST 25: a route whose tools declare no header parameter
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "gateway-credential" },
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 26: an undeclared header parameter never reaches the API
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPet","arguments":{"pathParameters":{"petId":7},"headerParameters":{"Authorization":"attacker","X-Forwarded-For":"10.0.0.1"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_auth'])
print(inner['data'].get('seen_forwarded'))
"
--- response_body
gateway-credential
None



=== TEST 27: an undeclared query parameter is rejected when the container declares one
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPet","arguments":{"pathParameters":{"petId":7},"queryParameters":{"verbose":false,"admin":"true"}}}}' "
print(d['result']['isError'])
"
--- response_body
True



=== TEST 28: a route whose tool declares a header parameter
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "gateway-credential" },
                    openapi_url = "http://127.0.0.1:11460/headerparam.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 29: a declared header parameter is sent, but cannot carry a newline
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"traced","arguments":{"headerParameters":{"X-Trace":"abc"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data'].get('seen_trace'))
"
--- response_body
abc



=== TEST 30: a newline in a declared header parameter drops the header
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"traced","arguments":{"headerParameters":{"X-Trace":"v\r\nX-Injected: 1"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data'].get('seen_trace'), inner['data'].get('seen_injected'))
print(inner['status'])
"
--- response_body
None None
200
--- error_log
cannot appear in a request header



=== TEST 31: a declared header parameter cannot replace the route's credential
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"traced","arguments":{"headerParameters":{"Authorization":"attacker"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_auth'])
"
--- response_body
gateway-credential



=== TEST 32: an undeclared query parameter is dropped when the tool declares none
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"traced","arguments":{"queryParameters":{"admin":"true"}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_path'])
"
--- response_body
/traced
