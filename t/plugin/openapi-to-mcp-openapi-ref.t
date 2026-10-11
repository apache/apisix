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

=== TEST 1: internal ref is expanded
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {
                components = { schemas = { Pet = { type = "object" } } },
                paths = { ["/p"] = { get = { responses = { ["$ref"] = "#/components/schemas/Pet" } } } },
            }
            local out = ref.resolve(spec)
            ngx.say(out.paths["/p"].get.responses.type)
        }
    }
--- response_body
object



=== TEST 2: json pointer escapes are decoded in the right order
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {
                components = { schemas = { ["a/b~c"] = { type = "string" } } },
                x = { ["$ref"] = "#/components/schemas/a~1b~0c" },
            }
            local out = ref.resolve(spec)
            ngx.say(out.x.type)
        }
    }
--- response_body
string



=== TEST 3: a file or relative ref degrades
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            -- these would name a file on the gateway's own filesystem
            local out = ref.resolve({
                a = { ["$ref"] = "./common.yaml#/Pet" },
                b = { ["$ref"] = "common.json#/components/schemas/Pet" },
            })
            ngx.say(out.a.type, " ", out.b.type)
        }
    }
--- response_body
object object
--- error_log
only internal and http(s) $ref is supported



=== TEST 4: dangling pointer degrades
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local out = ref.resolve({ x = { ["$ref"] = "#/components/schemas/Missing" } })
            ngx.say(out.x.type)
        }
    }
--- response_body
object
--- error_log
failed to resolve $ref



=== TEST 5: a circular ref is cut at the first repeat, not unrolled
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {
                components = { schemas = {
                    Node = { type = "object", properties = { next = { ["$ref"] = "#/components/schemas/Node" } } },
                } },
                x = { ["$ref"] = "#/components/schemas/Node" },
            }
            local out = ref.resolve(spec)

            -- one level of Node, then the self-reference degrades. Unrolling to
            -- MAX_DEPTH would emit a schema many times this size.
            local cur, depth = out.x, 0
            while cur and cur.properties and cur.properties.next do
                cur = cur.properties.next
                depth = depth + 1
                if depth > 40 then break end
            end
            ngx.say(depth)
            ngx.say(cur.type)
            ngx.say(cur.properties == nil)
        }
    }
--- response_body
1
object
true



=== TEST 6: two schemas referring to each other also degrade at the repeat
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {
                components = { schemas = {
                    A = { type = "object", properties = { b = { ["$ref"] = "#/components/schemas/B" } } },
                    B = { type = "object", properties = { a = { ["$ref"] = "#/components/schemas/A" } } },
                } },
                x = { ["$ref"] = "#/components/schemas/A" },
            }
            local out = ref.resolve(spec)
            ngx.say(out.x.properties.b.properties.a.type)
            ngx.say(out.x.properties.b.properties.a.properties == nil)
        }
    }
--- response_body
object
true



=== TEST 7: input spec is not mutated
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {
                components = { schemas = { Pet = { type = "object" } } },
                x = { ["$ref"] = "#/components/schemas/Pet" },
            }
            ref.resolve(spec)
            ngx.say(spec.x["$ref"])
        }
    }
--- response_body
#/components/schemas/Pet



=== TEST 8: an http ref is fetched, and its own internal refs resolve there
--- http_config
    server {
        listen 11490;
        location /target.json {
            content_by_lua_block {
                ngx.header["Content-Type"] = "application/json"
                ngx.print([==[{
                    "components": { "schemas": {
                        "Name": { "type": "string", "maxLength": 8 },
                        "Pet": { "type": "object", "properties": {
                            "who": { "$ref": "#/components/schemas/Name" } } }
                    } }
                }]==])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local out = ref.resolve({
                x = { ["$ref"] = "http://127.0.0.1:11490/target.json#/components/schemas/Pet" },
            })
            ngx.say(out.x.type)
            -- the inner "#/components/schemas/Name" is a pointer into the
            -- fetched document, not into the spec that named it
            ngx.say(out.x.properties.who.type, " ", out.x.properties.who.maxLength)
        }
    }
--- response_body
object
string 8



=== TEST 9: a whole-document http ref carries no fragment
--- http_config
    server {
        listen 11490;
        location /target.json {
            content_by_lua_block {
                ngx.header["Content-Type"] = "application/json"
                ngx.print([==[{"type": "object", "title": "whole"}]==])
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } })
            ngx.say(out.x.type, " ", out.x.title)
        }
    }
--- response_body
object whole



=== TEST 10: an http ref that cannot be fetched degrades
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            -- port 1 refuses immediately, so this does not wait for a timeout
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:1/a.json#/Pet" } })
            ngx.say(out.x.type)
        }
    }
--- response_body
object
--- error_log
failed to fetch an external $ref document



=== TEST 11: a failed document is not re-fetched for every reference to it
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {}
            for i = 1, 5 do
                spec["k" .. i] = { ["$ref"] = "http://127.0.0.1:1/a.json#/Pet" }
            end
            local out = ref.resolve(spec)
            ngx.say(out.k1.type, " ", out.k5.type)
        }
    }
--- response_body
object object
--- grep_error_log eval
qr/failed to fetch an external \$ref document/
--- grep_error_log_out
failed to fetch an external $ref document



=== TEST 12: no more than eight external documents are pulled in
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local spec = {}
            for i = 1, 12 do
                spec["k" .. i] = { ["$ref"] = "http://127.0.0.1:1/doc" .. i .. ".json#/Pet" }
            end
            local out = ref.resolve(spec)
            ngx.say(out.k1.type)
        }
    }
--- response_body
object
--- error_log
too many external $ref documents
