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
            }, { allowed_hosts = { "127.0.0.1" } })
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
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } },
                                   { allowed_hosts = { "127.0.0.1" } })
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
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:1/a.json#/Pet" } },
                                   { allowed_hosts = { "127.0.0.1" } })
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
            local out = ref.resolve(spec, { allowed_hosts = { "127.0.0.1" } })
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
            local out = ref.resolve(spec, { allowed_hosts = { "127.0.0.1" } })
            ngx.say(out.k1.type)
        }
    }
--- response_body
object
--- error_log
too many external $ref documents



=== TEST 13: an http ref to another host is not followed
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } },
                                    { base_origin = "http://example.com:80" })
            ngx.say(out.x.type)
        }
    }
--- response_body
object
--- error_log
points at a host that is not allowed



=== TEST 14: allowed_ref_hosts lets a named host through
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
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } },
                                    { base_origin = "http://example.com:80",
                                      allowed_hosts = { "127.0.0.1" } })
            ngx.say(out.x.type, " ", out.x.title)
        }
    }
--- response_body
object whole



=== TEST 15: a wildcard entry matches a subdomain
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            local ok = { "*.example.com", "other.test" }
            local out = ref.resolve({
                a = { ["$ref"] = "http://specs.example.com/a.json#/Pet" },
                b = { ["$ref"] = "http://evil.test/b.json#/Pet" },
            }, { base_origin = "http://docs.test:80", allowed_hosts = ok })
            -- both degrade: one cannot be reached, the other is not allowed
            ngx.say(out.a.type, " ", out.b.type)
        }
    }
--- response_body
object object
--- error_log
points at a host that is not allowed



=== TEST 16: expansion stops at the node budget
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            -- every level fans out four ways, so inlining would produce 4^16
            -- nodes without a budget
            local spec = { components = { schemas = {} } }
            for level = 1, 15 do
                local next_ref = "#/components/schemas/L" .. (level + 1)
                spec.components.schemas["L" .. level] = {
                    type = "object",
                    properties = {
                        a = { ["$ref"] = next_ref },
                        b = { ["$ref"] = next_ref },
                        c = { ["$ref"] = next_ref },
                        d = { ["$ref"] = next_ref },
                    },
                }
            end
            spec.components.schemas.L16 = { type = "string" }
            spec.root = { ["$ref"] = "#/components/schemas/L1" }

            local started = ngx.now()
            local out = ref.resolve(spec)
            ngx.update_time()
            ngx.say(type(out.root) == "table")
            ngx.say(ngx.now() - started < 5)
        }
    }
--- response_body
true
true
--- error_log
$ref expansion exceeded



=== TEST 17: the document's own origin includes its port
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
            -- another port of the same address is another origin: on a gateway
            -- it is where the Admin API and etcd answer
            local out = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } },
                                    { base_origin = "http://127.0.0.1:11491" })
            ngx.say("other port: ", out.x.type, " ", tostring(out.x.title))

            local origin = ref.origin_of("http://127.0.0.1:11490/spec.json")
            local same = ref.resolve({ x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } },
                                     { base_origin = origin })
            ngx.say("own port: ", same.x.type, " ", same.x.title)
        }
    }
--- response_body
other port: object nil
own port: object whole
--- error_log
points at a host that is not allowed



=== TEST 18: an allowed_ref_hosts entry may name the port it allows
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
            local spec = { x = { ["$ref"] = "http://127.0.0.1:11490/target.json" } }

            ngx.say("named port: ",
                    ref.resolve(spec, { allowed_hosts = { "127.0.0.1:11490" } }).x.title)
            ngx.say("other port: ",
                    tostring(ref.resolve(spec, { allowed_hosts = { "127.0.0.1:11491" } }).x.title))
            -- an entry with no port means that host on any port
            ngx.say("no port: ",
                    ref.resolve(spec, { allowed_hosts = { "127.0.0.1" } }).x.title)
        }
    }
--- response_body
named port: whole
other port: nil
no port: whole
--- error_log
points at a host that is not allowed



=== TEST 19: the budget is spent on expansion, not on the document's own size
--- config
    location /t {
        content_by_lua_block {
            local ref = require("apisix.plugins.openapi-to-mcp.openapi.ref")
            -- large enough to exceed the node budget on its own, with no $ref
            -- anywhere in it. Nothing may degrade: paths is the only subtree
            -- tools are generated from, and Lua does not define which subtree
            -- the traversal reaches first.
            local spec = { openapi = "3.0.0", components = { schemas = {} },
                           paths = { ["/pet"] = { get = { operationId = "getPet" } } } }
            for i = 1, 30000 do
                spec.components.schemas["S" .. i] = { type = "object", title = "t" .. i }
            end

            local out = ref.resolve(spec)
            ngx.say("paths: ", type(out.paths))
            ngx.say("operation: ", tostring(out.paths["/pet"].get.operationId))
            ngx.say("components: ", type(out.components.schemas.S30000))
        }
    }
--- response_body
paths: table
operation: getPet
components: table
