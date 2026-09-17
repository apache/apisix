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

    server {
        listen 11451;

        location / {
            content_by_lua_block {
                local api_key = ngx.req.get_headers()["api_key"] or ""
                ngx.log(ngx.INFO, "request: ", ngx.var.request_uri,
                        ", upstream received header api_key: ", api_key)
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{}')
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
            local plugin = require("apisix.plugins.openapi-to-mcp")
            local ok, err = plugin.check_schema({
                base_url = "http://127.0.0.1:11460",
                headers = {
                    ["Authorization"] = "test-api-key"
                },
                openapi_url = "http://127.0.0.1:11460/petstore.json"
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



=== TEST 2: missing required fields
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openapi-to-mcp")
            local ok, err = plugin.check_schema({
                base_url = "http://127.0.0.1:11460"
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body
property "openapi_url" is required



=== TEST 3: create a route with openapi-to-mcp plugin
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "test-api-key" },
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 4: a GET on an sse route advertises the message endpoint
--- exec
timeout 1 curl -X GET -N -sS http://localhost:1984/mcp 2>&1 | cat
--- response_body_like
event:\s*endpoint
data:\s*/mcp\?sessionId=.*



=== TEST 5: a message POST without a sessionId is rejected
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp 2>&1 | cat
--- response_body eval
qr/Missing or invalid sessionId parameter/



=== TEST 6: create a route with openapi-to-mcp plugin that using streamable http transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "test-api-key" },
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 7: tools/list is answered in-process
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/event: message\ndata: .*"tools":\[/



=== TEST 8: openapi-to-mcp's headers can use variables
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { Authorization = "${arg_username}-${http_apikey}" },
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 9: confirm that variables in headers are correctly replaced
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp?username=alice \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"findPetsByStatus","arguments":{"queryParameters":{"status":"sold"}}}}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "apikey: user-key" \
    2>&1 | cat
--- response_body eval
qr/alice-user-key/



=== TEST 10: streamable_http without headers
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 11: mcp request should be working when no headers in plugin config
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/event: message\ndata: .*"tools":\[/



=== TEST 12: base_url can use variables
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    base_url = "http://${http_variable_host}",
                    headers = { Authorization = "test-api-key" },
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 13: a GET on an sse route with a variable base_url advertises the message endpoint
--- exec
timeout 1 curl -X GET -N -sS http://localhost:1984/mcp \
    -H "variable_host: 127.0.0.1:11460" \
    2>&1 | cat
--- response_body_like
event:\s*endpoint
data:\s*/mcp\?sessionId=.*



=== TEST 14: schema validation with flatten_parameters
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openapi-to-mcp")
            for _, flatten in ipairs({ true, false }) do
                local ok, err = plugin.check_schema({
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                    flatten_parameters = flatten,
                })
                if not ok then
                    ngx.say(err)
                    return
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 15: an sse route with flatten_parameters
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                    flatten_parameters = true,
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 16: an sse route with flatten_parameters still opens a stream
--- exec
timeout 1 curl -X GET -N -sS http://localhost:1984/mcp 2>&1 | cat
--- response_body_like
event:\s*endpoint
data:\s*/mcp\?sessionId=.*



=== TEST 17: flatten_parameters in streamable_http transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                    flatten_parameters = true,
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 18: flattened parameters are not nested under queryParameters
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/(?s)^(?=.*"tools":\[)(?:(?!queryParameters).)*$/



=== TEST 19: flatten_parameters false in streamable_http transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                    flatten_parameters = false,
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 20: nested parameters are grouped under queryParameters
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/queryParameters/



=== TEST 21: verify mcp tools call works
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "findPetsByStatus",
      "arguments": {
        "queryParameters": {
          "status": "pending"
          }
        }
      },
      "id": 1
    }' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/findByStatus\?status=pending/



=== TEST 22: headerParameters appears in inputSchema for endpoints with in:header params (nested mode)
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/headerParameters/



=== TEST 23: tools/call with no headerParameters argument still works
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "deletePet",
      "arguments": {
        "pathParameters": {
          "petId": 9999
        }
      }
    },
    "id": 1
    }' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/(?s)(?=.*"jsonrpc":"2.0")(?=.*pet\/9999)/



=== TEST 24: route with flatten_parameters=true to check header params appear as top-level properties
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11451",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                    flatten_parameters = true,
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 25: headerParameters container is absent in flattened mode
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/(?s)^(?=.*"api_key")(?:(?!headerParameters).)*$/



=== TEST 26: tools/call forwards flattened header params as HTTP headers to upstream
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "deletePet",
      "arguments": {
        "petId": 1,
        "api_key": "flat-api-key"
      }
    },
    "id": 1
    }' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/"jsonrpc":"2.0"/
--- error_log
upstream received header api_key: flat-api-key



=== TEST 27: route with base_url pointing to header-capture server
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11451",
                    openapi_url = "http://127.0.0.1:11460/petstore.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 28: tools/call forwards headerParameters as HTTP headers to upstream
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "deletePet",
      "arguments": {
        "pathParameters": {
          "petId": 1
        },
        "headerParameters": {
          "api_key": "special-api-key"
        }
      }
    },
    "id": 1
    }' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/"jsonrpc":"2.0"/
--- error_log
upstream received header api_key: special-api-key



=== TEST 29: a route needs no upstream of its own
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/mcp",
                "plugins": { "openapi-to-mcp": {
                    "transport": "streamable_http",
                    "base_url": "http://127.0.0.1:11460",
                    "openapi_url": "http://127.0.0.1:11460/petstore.json"
                } }
            }]])
            ngx.say(code < 300 and "passed" or body)
        }
    }
--- response_body
passed



=== TEST 30: tools/list on a route without an upstream
--- max_size: 2048000
--- exec
timeout 1 curl -X POST -N -sS http://localhost:1984/mcp \
    -d '{"method":"tools/list","jsonrpc":"2.0","id":1}' \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    2>&1 | cat
--- response_body eval
qr/event: message\ndata: .*"name":"findPetsByStatus"/



=== TEST 31: an sse route without an upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/mcp",
                "plugins": { "openapi-to-mcp": {
                    "transport": "sse",
                    "base_url": "http://127.0.0.1:11460",
                    "openapi_url": "http://127.0.0.1:11460/petstore.json"
                } }
            }]])
            ngx.say(code < 300 and "passed" or body)
        }
    }
--- response_body
passed



=== TEST 32: the stream opens and nothing is proxied
--- exec
timeout 1 curl -X GET -N -sS http://localhost:1984/mcp 2>&1 | cat
--- response_body_like
event:\s*endpoint
data:\s*/mcp\?sessionId=.*
--- no_error_log
failed to fetch upstream



=== TEST 33: a route over an API that answers with a large body
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/large.json",
                    max_response_body_size = 65536,
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 34: a response over the limit fails the call instead of buffering it
--- max_size: 2048000
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getLarge","arguments":{}}}' "
print(d['result']['isError'])
inner = json.loads(d['result']['content'][0]['text'])
print(inner['error']['code'])
"
--- response_body
True
RESPONSE_TOO_LARGE
--- error_log
exceeded max_response_body_size



=== TEST 35: a response under the limit still comes back whole
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/large.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 36: the whole body is read below the default limit
--- max_size: 8192000
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getLarge","arguments":{"queryParameters":{"size":1000}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['status'], len(inner['data']['blob']))
"
--- response_body
200 1000



=== TEST 37: a route that names the origins it expects
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
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



=== TEST 38: a request from an allowed origin is served
--- request
POST /mcp
{"jsonrpc":"2.0","id":1,"method":"ping"}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
Origin: https://app.example.com
--- response_body eval
qr/"result":\{\}/



=== TEST 39: a request from another origin is refused
--- request
POST /mcp
{"jsonrpc":"2.0","id":1,"method":"ping"}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
Origin: https://evil.example.com
--- error_code: 403
--- response_body
{"message":"Origin not allowed"}
--- error_log
rejected an MCP request with a disallowed Origin



=== TEST 40: a request without an Origin header is still served
--- request
POST /mcp
{"jsonrpc":"2.0","id":1,"method":"ping"}
--- more_headers
Content-Type: application/json
Accept: application/json, text/event-stream
--- response_body eval
qr/"result":\{\}/



=== TEST 41: a configured header cannot carry a newline
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openapi-to-mcp")
            local cases = {
                { ["X-Trace"] = "ok" },
                { ["X-Trace"] = "bad\r\nX-Injected: 1" },
                { ["X-Trace\r\nX-Injected"] = "1" },
                { ["X Trace"] = "1" },
            }
            for i, headers in ipairs(cases) do
                local ok = plugin.check_schema({
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                    headers = headers,
                })
                ngx.say(i, ": ", tostring(ok ~= nil and ok ~= false))
            end
        }
    }
--- response_body
1: true
2: false
3: false
4: false



=== TEST 42: the API receives the Host it was reached on, port included
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPet","arguments":{"pathParameters":{"petId":7}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data']['seen_host'])
"
--- response_body
127.0.0.1:11460



=== TEST 43: a route over an API that ends its body by closing the connection
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/closing.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 44: a connection-close-delimited body is read whole, not reported as an error
--- max_size: 2048000
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getClosing","arguments":{}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['status'], inner['data']['closed'], len(inner['data']['blob']))
"
--- response_body
200 True 1024



=== TEST 45: a body larger than one read chunk is reassembled
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/large.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 46: the chunks add up to the whole body
--- max_size: 8192000
--- exec
python3 t/plugin/openapi_to_mcp_harness.py /mcp \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getLarge","arguments":{"queryParameters":{"size":200000}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['status'], len(inner['data']['blob']))
"
--- response_body
200 200000



=== TEST 47: a configured header cannot end with a newline either
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openapi-to-mcp")
            local cases = {
                { ["X-Trace"] = "trailing\n" },
                { ["X-Trace\n"] = "1" },
            }
            for i, headers in ipairs(cases) do
                local ok = plugin.check_schema({
                    base_url = "http://127.0.0.1:11460",
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                    headers = headers,
                })
                ngx.say(i, ": ", tostring(ok ~= nil and ok ~= false))
            end
        }
    }
--- response_body
1: false
2: false



=== TEST 48: a route header built from a variable
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11460",
                    headers = { ["X-Trace"] = "${arg_trace}" },
                    openapi_url = "http://127.0.0.1:11460/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 49: a newline arriving through that variable drops the header
--- exec
python3 t/plugin/openapi_to_mcp_harness.py '/mcp?trace=a%0d%0aX-Injected:%201' \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getPet","arguments":{"pathParameters":{"petId":7}}}}' "
inner = json.loads(d['result']['content'][0]['text'])
print(inner['data'].get('seen_trace'), inner['data'].get('seen_injected'))
"
--- response_body
None None
--- error_log
cannot appear in a request header
