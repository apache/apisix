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

=== TEST 1: integer is left as-is
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({ type = "integer" })
            ngx.say(core.json.encode(out))
        }
    }
--- response_body
{"type":"integer"}



=== TEST 2: nullable integer becomes ["integer","null"]
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({ type = "integer", nullable = true })
            ngx.say(core.json.encode(out.type))
            ngx.say(out.nullable == nil)
        }
    }
--- response_body
["integer","null"]
true



=== TEST 3: openapi-only keys are stripped
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({
                type = "string",
                xml = { name = "x" },
                externalDocs = { url = "http://e" },
                deprecated = true,
                readOnly = true,
                writeOnly = true,
            })
            local keys = {}
            for k in pairs(out) do keys[#keys+1] = k end
            table.sort(keys)
            ngx.say(table.concat(keys, ","))
        }
    }
--- response_body
type



=== TEST 4: nested properties and array items recurse
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({
                type = "object",
                properties = {
                    n = { type = "integer" },
                    list = { type = "array", items = { type = "integer" } },
                },
            })
            ngx.say(out.properties.n.type)
            ngx.say(out.properties.list.items.type)
        }
    }
--- response_body
integer
integer



=== TEST 5: cycle degrades to generic object
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local node = { type = "object", properties = {} }
            node.properties.self = node
            local out = schema.to_json_schema(node)
            ngx.say(out.properties.self.type)
        }
    }
--- response_body
object
--- error_log
cycle detected in schema



=== TEST 6: unresolved $ref degrades to generic object
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({ ["$ref"] = "#/components/schemas/Pet" })
            ngx.say(out.type)
        }
    }
--- response_body
object
--- error_log
unresolved $ref



=== TEST 7: a nullable object deliberately stops converting its children
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            -- The nullable rewrite turns type into an array, and the recursion
            -- checks below it test for the string "object". The children are
            -- therefore left alone, on purpose: the generated tool list stays
            -- stable for existing clients.
            local out = schema.to_json_schema({
                type = "object",
                nullable = true,
                properties = { inner = { type = "string", readOnly = true, xml = { name = "x" } } },
            })
            ngx.say(core.json.encode(out.type))
            ngx.say(out.properties.inner.readOnly)
            ngx.say(out.properties.inner.xml ~= nil)
        }
    }
--- response_body
["object","null"]
true
true



=== TEST 8: a nullable array likewise leaves its items untouched
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({
                type = "array",
                nullable = true,
                items = { ["$ref"] = "#/components/schemas/Pet" },
            })
            ngx.say(out.items["$ref"])
        }
    }
--- response_body
#/components/schemas/Pet



=== TEST 9: composition keywords are converted even without a parent type
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({
                allOf = {
                    { type = "object", properties = { a = { type = "string", readOnly = true } } },
                    { type = "object", properties = { b = { type = "string", nullable = true } } },
                },
            })
            ngx.say(out.allOf[1].properties.a.readOnly == nil)
            ngx.say(core.json.encode(out.allOf[2].properties.b.type))
        }
    }
--- response_body
true
["string","null"]



=== TEST 10: oneOf and anyOf recurse the same way
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.plugins.openapi-to-mcp.openapi.schema")
            local out = schema.to_json_schema({
                oneOf = { { type = "object", properties = { x = { type = "string", xml = {} } } } },
                anyOf = { { type = "object", properties = { y = { type = "string", deprecated = true } } } },
            })
            ngx.say(out.oneOf[1].properties.x.xml == nil)
            ngx.say(out.anyOf[1].properties.y.deprecated == nil)
        }
    }
--- response_body
true
true
