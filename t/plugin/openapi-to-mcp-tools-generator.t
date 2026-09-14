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

=== TEST 1: title_case lowercases first, so {userId} becomes Userid
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            ngx.say(g.title_case("pet"))
            ngx.say(g.title_case("user-posts"))
            ngx.say(g.title_case("user_posts"))
            ngx.say(g.title_case("{userId}"))
            ngx.say(g.title_case("{petId}"))
        }
    }
--- response_body
Pet
UserPosts
UserPosts
Userid
Petid



=== TEST 2: gen_operation_id only appends By for a trailing path parameter
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            ngx.say(g.gen_operation_id("get", "/pet/{petId}"))
            ngx.say(g.gen_operation_id("get", "/users/{userId}/posts"))
            ngx.say(g.gen_operation_id("post", "/pet"))
            ngx.say(g.gen_operation_id("get", "/"))
        }
    }
--- response_body
GetPetByPetid
GetUsersPosts
PostPet
GetRoot



=== TEST 3: operationId from the spec wins over the generated one
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/pet"] = { get = { operationId = "listPets" } } } }
            local tools = g.generate(spec, { ["/pet"] = 1 }, {})
            ngx.say(tools[1].name)
        }
    }
--- response_body
listPets



=== TEST 4: tool names are sanitized to [A-Za-z0-9_-]
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/a"] = { get = { operationId = "pets.list v2" } } } }
            local tools = g.generate(spec, { ["/a"] = 1 }, {})
            ngx.say(tools[1].name)
        }
    }
--- response_body
pets_list_v2



=== TEST 5: duplicate names get a numeric suffix
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = {
                ["/a"] = { get = { operationId = "dup" }, post = { operationId = "dup" } },
                ["/b"] = { get = { operationId = "dup" } },
            } }
            local tools = g.generate(spec, { ["/a"] = 1, ["/b"] = 2 }, {})
            local names = {}
            for _, t in ipairs(tools) do names[#names+1] = t.name end
            ngx.say(table.concat(names, ","))
        }
    }
--- response_body
dup,dup_1,dup_2



=== TEST 6: description falls back description -> summary -> Executes
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = {
                ["/a"] = { get = { description = "D", summary = "S" } },
                ["/b"] = { get = { summary = "S only" } },
                ["/c"] = { get = {} },
            } }
            local tools = g.generate(spec, { ["/a"] = 1, ["/b"] = 2, ["/c"] = 3 }, {})
            ngx.say(tools[1].description)
            ngx.say(tools[2].description)
            ngx.say(tools[3].description)
        }
    }
--- response_body
D
S only
Executes GET /c



=== TEST 7: annotations are inferred from the http method
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/a"] = {
                get = {}, put = {}, delete = {}, post = {},
            } } }
            local tools = g.generate(spec, { ["/a"] = 1 }, {})
            ngx.say(tools[1].method, " ", tostring(tools[1].annotations.readOnlyHint))
            ngx.say(tools[2].method, " ", tostring(tools[2].annotations.idempotentHint))
            ngx.say(tools[3].method, " ", tostring(tools[3].annotations))
            ngx.say(tools[4].method, " ", tostring(tools[4].annotations.destructiveHint),
                    " ", tostring(tools[4].annotations.idempotentHint))
        }
    }
--- response_body
get true
put true
post nil
delete true true



=== TEST 8: x-mcp-annotations overrides the inferred ones
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/a"] = { get = {
                ["x-mcp-annotations"] = { title = "  My Tool  ", readOnlyHint = false, openWorldHint = true },
            } } } }
            local tools = g.generate(spec, { ["/a"] = 1 }, {})
            ngx.say(tools[1].annotations.title)
            ngx.say(tostring(tools[1].annotations.readOnlyHint))
            ngx.say(tostring(tools[1].annotations.openWorldHint))
        }
    }
--- response_body
My Tool
false
true



=== TEST 9: invalid x-mcp-annotations entries are ignored with a warning
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/a"] = { get = {
                operationId = "op",
                ["x-mcp-annotations"] = { title = "   ", readOnlyHint = "yes", bogus = 1 },
            } } } }
            local tools = g.generate(spec, { ["/a"] = 1 }, {})
            ngx.say(tools[1].annotations.title == nil)
            -- inferred readOnlyHint survives because the invalid override is dropped
            ngx.say(tostring(tools[1].annotations.readOnlyHint))
            ngx.say(tools[1].annotations.bogus == nil)
        }
    }
--- response_body
true
true
true
--- error_log
ignoring invalid x-mcp-annotations



=== TEST 10: flatten mode puts path, query and header params at top level
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "petId", ["in"] = "path", required = true, schema = { type = "integer" } },
                { name = "limit", ["in"] = "query", schema = { type = "integer" } },
                { name = "X-Trace", ["in"] = "header", required = true, schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, true)
            ngx.say(s.properties.petId.type)
            ngx.say(s.properties.limit.type)
            ngx.say(s.properties["X-Trace"].type)
            ngx.say(table.concat(s.required, ","))
            ngx.say(s.properties.pathParameters == nil)
        }
    }
--- response_body
integer
integer
string
petId,X-Trace
true



=== TEST 11: flatten mode has a three-level description fallback with a prefix
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "a", ["in"] = "path", schema = { type = "string" } },
                { name = "b", ["in"] = "query", schema = { type = "string", description = "from schema" } },
                { name = "c", ["in"] = "header", description = "from param", schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, true)
            ngx.say(s.properties.a.description)
            ngx.say(s.properties.b.description)
            ngx.say(s.properties.c.description)
        }
    }
--- response_body
Path parameter: a
from schema
from param



=== TEST 12: nested mode groups params into three containers
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "petId", ["in"] = "path", required = true, schema = { type = "integer" } },
                { name = "limit", ["in"] = "query", schema = { type = "integer" } },
                { name = "X-Trace", ["in"] = "header", schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, false)
            ngx.say(s.properties.pathParameters.properties.petId.type)
            ngx.say(s.properties.queryParameters.properties.limit.type)
            ngx.say(s.properties.headerParameters.properties["X-Trace"].type)
            ngx.say(s.properties.petId == nil)
        }
    }
--- response_body
integer
integer
string
true



=== TEST 13: nested containers set additionalProperties and propagate required
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "petId", ["in"] = "path", required = true, schema = { type = "string" } },
                { name = "limit", ["in"] = "query", schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, false)
            ngx.say(tostring(s.properties.pathParameters.additionalProperties))
            ngx.say(table.concat(s.properties.pathParameters.required, ","))
            ngx.say(table.concat(s.required, ","))
            -- queryParameters has no required member, so it is not listed at the top
            ngx.say(s.properties.queryParameters.required == nil)
        }
    }
--- response_body
false
petId
pathParameters
true



=== TEST 14: nested mode has no third-level description default
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "a", ["in"] = "path", schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, false)
            ngx.say(s.properties.pathParameters.properties.a.description == nil)
        }
    }
--- response_body
true



=== TEST 15: json request body becomes the requestBody property
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { requestBody = {
                required = true,
                content = { ["application/json"] = { schema = { type = "object" } } },
            } }
            local s, params, ct = g.build_input_schema(op, false)
            ngx.say(ct)
            ngx.say(s.properties.requestBody.type)
            ngx.say(s.properties.requestBody.description)
            ngx.say(table.concat(s.required, ","))
        }
    }
--- response_body
application/json
object
The JSON request body.
requestBody



=== TEST 16: non-json request body degrades to a string
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { requestBody = {
                content = { ["text/plain"] = { schema = { type = "string" } } },
            } }
            local s, params, ct = g.build_input_schema(op, false)
            ngx.say(ct)
            ngx.say(s.properties.requestBody.type)
            ngx.say(s.properties.requestBody.description)
            ngx.say(s.required == nil)
        }
    }
--- response_body
text/plain
string
Request body (content type: text/plain)
true



=== TEST 17: empty required list is omitted entirely
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local s = g.build_input_schema({}, false)
            ngx.say(s.type)
            ngx.say(s.required == nil)
        }
    }
--- response_body
object
true



=== TEST 18: generate carries method, path template and execution parameters
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/pet/{petId}"] = { get = {
                operationId = "getPet",
                parameters = {
                    { name = "petId", ["in"] = "path", required = true, schema = { type = "string" } },
                    { name = "verbose", ["in"] = "query", schema = { type = "boolean" } },
                },
            } } } }
            local tools = g.generate(spec, { ["/pet/{petId}"] = 1 }, {})
            local t = tools[1]
            ngx.say(t.method, " ", t.path_template)
            ngx.say(t.execution_parameters[1].name, "/", t.execution_parameters[1]["in"])
            ngx.say(t.execution_parameters[2].name, "/", t.execution_parameters[2]["in"])
        }
    }
--- response_body
get /pet/{petId}
petId/path
verbose/query



=== TEST 19: tool order follows path order then method enum order
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = {
                ["/zebra"] = { post = { operationId = "zp" }, get = { operationId = "zg" } },
                ["/apple"] = { get = { operationId = "ag" } },
            } }
            local tools = g.generate(spec, { ["/zebra"] = 1, ["/apple"] = 2 }, {})
            local names = {}
            for _, t in ipairs(tools) do names[#names+1] = t.name end
            ngx.say(table.concat(names, ","))
        }
    }
--- response_body
zg,zp,ag



=== TEST 20: flatten_parameters option reaches build_input_schema
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/a"] = { get = {
                operationId = "op",
                parameters = { { name = "q", ["in"] = "query", schema = { type = "string" } } },
            } } } }
            local flat = g.generate(spec, { ["/a"] = 1 }, { flatten_parameters = true })
            local nested = g.generate(spec, { ["/a"] = 1 }, { flatten_parameters = false })
            ngx.say(flat[1].input_schema.properties.q ~= nil)
            ngx.say(nested[1].input_schema.properties.queryParameters ~= nil)
        }
    }
--- response_body
true
true



=== TEST 21: the top level carries no $schema and no additionalProperties
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { requestBody = { content = { ["application/json"] = { schema = {
                type = "object",
                properties = { nested = { type = "object", properties = { deep = { type = "string" } } } },
            } } } } }
            local s = g.build_input_schema(op, false)
            ngx.say(s["$schema"] == nil)
            ngx.say(s.additionalProperties == nil)
            ngx.say(s.properties.requestBody.additionalProperties == nil)
            ngx.say(s.properties.requestBody.properties.nested.additionalProperties == nil)
        }
    }
--- response_body
true
true
true
true



=== TEST 22: an explicit additionalProperties is passed through untouched
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { requestBody = { content = { ["application/json"] = { schema = {
                type = "object",
                properties = { open = { type = "object", additionalProperties = true,
                                        properties = { k = { type = "string" } } } },
            } } } } }
            local s = g.build_input_schema(op, false)
            ngx.say(tostring(s.properties.requestBody.properties.open.additionalProperties))
        }
    }
--- response_body
true



=== TEST 23: objects inside array items keep their integer type and stay open
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { requestBody = { content = { ["application/json"] = { schema = {
                type = "object",
                properties = { arr = { type = "array", items = {
                    type = "object", properties = { i = { type = "integer" } },
                } } },
            } } } } }
            local s = g.build_input_schema(op, false)
            local items = s.properties.requestBody.properties.arr.items
            ngx.say(items.additionalProperties == nil)
            ngx.say(items.properties.i.type)
        }
    }
--- response_body
true
integer



=== TEST 24: nested parameter containers still close themselves
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { name = "petId", ["in"] = "path", required = true, schema = { type = "string" } },
            } }
            local s = g.build_input_schema(op, false)
            ngx.say(tostring(s.properties.pathParameters.additionalProperties))
            ngx.say(s.additionalProperties == nil)
        }
    }
--- response_body
false
true



=== TEST 25: a parameter without a name is skipped, not fatal
--- config
    location /t {
        content_by_lua_block {
            local g = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local op = { parameters = {
                { ["in"] = "query", schema = { type = "string" } },
                { name = "ok", ["in"] = "query", schema = { type = "string" } },
            } }
            local flat = g.build_input_schema(op, true)
            ngx.say(flat.properties.ok ~= nil)
            local nested = g.build_input_schema(op, false)
            ngx.say(nested.properties.queryParameters.properties.ok ~= nil)
        }
    }
--- response_body
true
true
--- error_log
skipping parameter without a name
