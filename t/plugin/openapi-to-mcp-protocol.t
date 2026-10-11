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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: result and error envelopes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local rpc = require("apisix.plugins.openapi-to-mcp.jsonrpc")
            local ok = rpc.result(1, {})
            ngx.say(ok.jsonrpc, ",", ok.id, ",", core.json.encode(ok.result))
            local err = rpc.error(2, rpc.ERR_METHOD_NOT_FOUND, "Method not found")
            ngx.say(err.jsonrpc, ",", err.id, ",", err.error.code, ",", err.error.message)
            ngx.say(err.error.data == nil, ",", err.result == nil)
        }
    }
--- response_body
2.0,1,{}
2.0,2,-32601,Method not found
true,true



=== TEST 2: a request without an id is a notification
--- config
    location /t {
        content_by_lua_block {
            local rpc = require("apisix.plugins.openapi-to-mcp.jsonrpc")
            ngx.say(rpc.is_notification({ jsonrpc = "2.0", method = "notifications/initialized" }))
            ngx.say(rpc.is_notification({ jsonrpc = "2.0", id = 1, method = "ping" }))
        }
    }
--- response_body
true
false



=== TEST 3: request shape validation
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local rpc = require("apisix.plugins.openapi-to-mcp.jsonrpc")
            ngx.say(rpc.validate({ jsonrpc = "2.0", id = 1, method = "ping" }))
            ngx.say(rpc.validate({ jsonrpc = "1.0", method = "ping" }))
            ngx.say(rpc.validate({ jsonrpc = "2.0" }))
            ngx.say(rpc.validate({ jsonrpc = "2.0", method = "ping", params = "x" }))
            ngx.say(rpc.validate("not a table"))
            -- an explicit null id is not a valid request id
            ngx.say(rpc.validate({ jsonrpc = "2.0", id = core.json.null, method = "ping" }))
            -- MCP wants params to be an object, never an array
            ngx.say(rpc.validate({ jsonrpc = "2.0", id = 1, method = "ping", params = { 1, 2 } }))
            -- an empty method passes shape validation and is answered -32601
            ngx.say(rpc.validate({ jsonrpc = "2.0", id = 1, method = "" }))
            -- a missing id is a notification, still legal
            ngx.say(rpc.validate({ jsonrpc = "2.0", method = "notifications/initialized" }))
        }
    }
--- response_body
true
false
false
false
false
false
false
true
true



=== TEST 4: the parse-error envelope always carries a null id
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local rpc = require("apisix.plugins.openapi-to-mcp.jsonrpc")
            local msg = rpc.invalid_message()
            ngx.say(msg.jsonrpc, ",", msg.error.code, ",", msg.error.message)
            ngx.say(core.json.encode(msg.id))
        }
    }
--- response_body
2.0,-32700,Parse error: Invalid JSON-RPC message
null



=== TEST 5: protocol version negotiation echoes known versions
--- config
    location /t {
        content_by_lua_block {
            local p = require("apisix.plugins.openapi-to-mcp.protocol")
            ngx.say(p.negotiate("2025-03-26"))
            ngx.say(p.negotiate("2024-11-05"))
            ngx.say(p.negotiate("2025-11-25"))
        }
    }
--- response_body
2025-03-26
2024-11-05
2025-11-25



=== TEST 6: an unknown version falls back to the latest
--- config
    location /t {
        content_by_lua_block {
            local p = require("apisix.plugins.openapi-to-mcp.protocol")
            ngx.say(p.negotiate("1999-01-01"))
            ngx.say(p.negotiate(nil))
            ngx.say(p.negotiate(42))
        }
    }
--- response_body
2025-11-25
2025-11-25
2025-11-25



=== TEST 7: capabilities and serverInfo
--- config
    location /t {
        content_by_lua_block {
            local p = require("apisix.plugins.openapi-to-mcp.protocol")
            local core = require("apisix.core")
            local caps = p.capabilities()
            ngx.say(core.json.encode(caps.tools))
            local info = p.server_info()
            ngx.say(info.name, ",", info.version)
        }
    }
--- response_body
{}
openapi2mcp,0.0.1
