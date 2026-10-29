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

=== TEST 1: methods follow the OpenAPIV3.HttpMethods enum order
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local spec = { paths = { ["/a"] = {
                patch = {}, get = {}, delete = {}, post = {}, put = {},
            } } }
            local out = endpoints.extract(spec, { ["/a"] = 1 })
            local names = {}
            for _, e in ipairs(out) do names[#names+1] = e.method end
            ngx.say(table.concat(names, ","))
        }
    }
--- response_body
get,put,post,delete,patch



=== TEST 2: paths follow document order, not alphabetical
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local spec = { paths = {
                ["/zebra"] = { get = {} },
                ["/apple"] = { get = {} },
            } }
            local out = endpoints.extract(spec, { ["/zebra"] = 1, ["/apple"] = 2 })
            ngx.say(out[1].path, ",", out[2].path)
        }
    }
--- response_body
/zebra,/apple



=== TEST 3: non-operation keys are skipped
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local spec = { paths = { ["/a"] = {
                get = {}, summary = "x", parameters = {}, servers = {},
            } } }
            local out = endpoints.extract(spec, { ["/a"] = 1 })
            ngx.say(#out, ",", out[1].method)
        }
    }
--- response_body
1,get



=== TEST 4: empty or missing paths yields empty list
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            ngx.say(#endpoints.extract({}, {}))
            ngx.say(#endpoints.extract({ paths = {} }, {}))
        }
    }
--- response_body
0
0



=== TEST 5: paths absent from path_order fall back to sorted order
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local spec = { paths = {
                ["/zebra"] = { get = {} },
                ["/apple"] = { get = {} },
            } }
            local out = endpoints.extract(spec, {})
            ngx.say(out[1].path, ",", out[2].path)
        }
    }
--- response_body
/apple,/zebra



=== TEST 6: operation table is carried through untouched
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local op = { operationId = "listPets", summary = "list" }
            local out = endpoints.extract({ paths = { ["/a"] = { get = op } } }, { ["/a"] = 1 })
            ngx.say(out[1].operation.operationId)
            ngx.say(out[1].operation == op)
            ngx.say(out[1]._path_rank == nil)
        }
    }
--- response_body
listPets
true
true



=== TEST 7: path item parameters are inherited, and an operation parameter overrides by name and location
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local get = {
                operationId = "getPet",
                parameters = {
                    { name = "verbose", ["in"] = "query", schema = { type = "string" } },
                    { name = "id", ["in"] = "header", schema = { type = "string" } },
                },
            }
            local spec = { paths = { ["/pets/{id}"] = {
                parameters = {
                    { name = "id", ["in"] = "path", required = true, schema = { type = "integer" } },
                    { name = "verbose", ["in"] = "query", schema = { type = "boolean" } },
                },
                get = get,
            } } }
            local out = endpoints.extract(spec, {})
            for _, p in ipairs(out[1].operation.parameters) do
                ngx.say(p["in"], " ", p.name, " ", p.schema.type)
            end
            -- the document itself is left alone
            ngx.say(#get.parameters, " ", out[1].operation ~= get, " ", out[1].operation.operationId)
        }
    }
--- response_body
query verbose string
header id string
path id integer
2 true getPet



=== TEST 8: an operation without parameters of its own takes the path item's
--- config
    location /t {
        content_by_lua_block {
            local endpoints = require("apisix.plugins.openapi-to-mcp.openapi.endpoints")
            local generator = require("apisix.plugins.openapi-to-mcp.tools.generator")
            local spec = { paths = { ["/pets/{id}"] = {
                parameters = {
                    { name = "id", ["in"] = "path", required = true, schema = { type = "integer" } },
                },
                delete = { operationId = "deletePet" },
            } } }
            local tool = generator.generate(spec, { ["/pets/{id}"] = 1 })[1]
            ngx.say(tool.input_schema.properties.pathParameters.properties.id.type)
            ngx.say(tool.input_schema.required[1])
            ngx.say(tool.execution_parameters[1]["in"], " ", tool.execution_parameters[1].name)
        }
    }
--- response_body
integer
pathParameters
path id
