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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}


repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - graphql-limit-count
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: cost engine - worked examples (complexity / node_quantifier)
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            -- schema index in the shape introspection.lua produces
            local schema = {
                query_type = "Query",
                mutation_type = "Mutation",
                types = {
                    Query = {fields = {allPeople = {type = "PeopleConnection"}}},
                    PeopleConnection = {fields = {people = {type = "Person"}}},
                    Person = {fields = {
                        name = {type = "String"},
                        vehicleConnection = {type = "VehicleConnection"},
                    }},
                    VehicleConnection = {fields = {vehicles = {type = "Vehicle"}}},
                    Vehicle = {fields = {
                        id = {type = "ID"},
                        name = {type = "String"},
                        cargoCapacity = {type = "Float"},
                        filmConnection = {type = "FilmConnection"},
                    }},
                    FilmConnection = {fields = {films = {type = "Film"}}},
                    Film = {fields = {
                        title = {type = "String"},
                        characterConnection = {type = "CharacterConnection"},
                    }},
                    CharacterConnection = {fields = {characters = {type = "Person"}}},
                },
            }

            local function raw_cost(query, decos, strategy)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost(strategy, operations, fragments,
                                       {decorations = cost.build_index(decos),
                                        schema = schema})
            end

            local q1 = [[
            query {
              allPeople(first: 20) {
                people {
                  name
                  vehicleConnection(first: 10) {
                    vehicles { id name cargoCapacity }
                  }
                }
              }
            }
            ]]

            -- worked example 1: 862
            ngx.say(raw_cost(q1, {
                {field_path = "Query.allPeople", mul_arguments = {"first"}},
                {field_path = "Person.vehicleConnection", mul_arguments = {"first"}},
            }, "complexity"))

            -- worked example 2: 4683
            ngx.say(raw_cost(q1, {
                {field_path = "Query.allPeople", mul_arguments = {"first"},
                 mul_value = 2, add_value = 2},
                {field_path = "Person.vehicleConnection", mul_arguments = {"first"},
                 add_value = 5},
                {field_path = "Vehicle.name", add_value = 8},
            }, "complexity"))

            local q3 = [[
            query {
              allPeople(first: 100) {
                people {
                  vehicleConnection(first: 10) {
                    vehicles {
                      filmConnection(first: 5) {
                        films {
                          characterConnection(first: 50) { characters { name } }
                        }
                      }
                    }
                  }
                }
              }
            }
            ]]

            local nq = {
                {field_path = "Query.allPeople", mul_arguments = {"first"}},
                {field_path = "Person.vehicleConnection", mul_arguments = {"first"}},
                {field_path = "Vehicle.filmConnection", mul_arguments = {"first"}},
                {field_path = "Film.characterConnection", mul_arguments = {"first"}},
            }

            -- worked example 3: 6101
            ngx.say(raw_cost(q3, nq, "node_quantifier"))

            -- worked example 4: cost 42 on Person.vehicleConnection -> 10201
            local nq42 = {
                {field_path = "Query.allPeople", mul_arguments = {"first"}},
                {field_path = "Person.vehicleConnection", mul_arguments = {"first"},
                 add_value = 42},
                {field_path = "Vehicle.filmConnection", mul_arguments = {"first"}},
                {field_path = "Film.characterConnection", mul_arguments = {"first"}},
            }
            ngx.say(raw_cost(q3, nq42, "node_quantifier"))
        }
    }
--- response_body
862
4683
6101
10201



=== TEST 2: cost engine - fragments, variables and undecorated queries
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {allPeople = {type = "PeopleConnection"}}},
                    PeopleConnection = {fields = {people = {type = "Person"}}},
                    Person = {fields = {name = {type = "String"}, id = {type = "ID"}}},
                },
            }

            local decos = cost.build_index({
                {field_path = "Query.allPeople", mul_arguments = {"first"}},
            })

            local function raw_cost(query, strategy, opts)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                opts = opts or {}
                opts.decorations = decos
                opts.schema = schema
                return cost.query_cost(strategy, operations, fragments, opts)
            end

            -- a fragment spread is expanded in place and costs nothing by itself:
            -- people -> {name} = 1 ; people = 2 ; allPeople = 2*20+1 = 41 ; op = 42
            ngx.say(raw_cost([[
                query { allPeople(first: 20) { people { ...pf } } }
                fragment pf on Person { name }
            ]], "complexity"))

            -- the same fragment spread twice counts twice
            ngx.say(raw_cost([[
                query { allPeople(first: 20) { people { ...pf ...pf } } }
                fragment pf on Person { name }
            ]], "complexity"))

            -- an inline fragment is transparent and does not move the type cursor
            ngx.say(raw_cost([[
                query { allPeople(first: 20) { people { ... on Person { name } } } }
            ]], "complexity"))

            -- a quantifier passed as a variable is not read by default, so cost is 0
            ngx.say(raw_cost([[
                query ($n: Int) { allPeople(first: $n) { people { name } } }
            ]], "node_quantifier"))

            -- ... unless resolve_variables is on
            ngx.say(raw_cost([[
                query ($n: Int) { allPeople(first: $n) { people { name } } }
            ]], "node_quantifier", {variables = {n = 100}}))

            -- node_quantifier without any quantifier in the query: 0 raw cost
            ngx.say(raw_cost([[
                query { allPeople { people { name } } }
            ]], "node_quantifier"))
        }
    }
--- response_body
42
62
42
0
1
0



=== TEST 3: schema check - reject an invalid score_factor / cost_strategy
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.graphql-limit-count")
            local ok, err = plugin.check_schema({
                count = 10, time_window = 60, score_factor = 0,
            })
            ngx.say(ok, " ", err)

            ok, err = plugin.check_schema({
                count = 10, time_window = 60, cost_strategy = "unknown",
            })
            ngx.say(ok, " ", err)

            -- decorations are a service sub resource, not a plugin field
            ok, err = plugin.check_schema({
                count = 10, time_window = 60,
                cost_decorations = {{field_path = "Query.products"}},
            })
            ngx.say(ok, " ", err)
        }
    }
--- response_body eval
qr/^false .*score_factor.*\nfalse .*cost_strategy.*\ntrue nil$/



=== TEST 4: set route: cost_strategy defaults to depth (backward compatible)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: hit - depth is still the cost, and it is reported as X-Graphql-Query-Cost
--- request
POST /graphql
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 4
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 96



=== TEST 6: set service + cost decorations + route for node_quantifier
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            local decorations = {
                {id = "d1", field_path = "Query.products",
                 mul_arguments = {"first"}, add_value = 1},
                {id = "d2", field_path = "Query.topProducts",
                 mul_arguments = {"first"}, add_value = 1},
                {id = "d3", field_path = "Product.reviews",
                 mul_arguments = {"first"}, add_value = 1},
                {id = "d4", field_path = "User.orders",
                 mul_arguments = {"first"}, add_value = 1},
            }
            for _, deco in ipairs(decorations) do
                local url = '/apisix/admin/services/shop-graphql/graphql_cost_decorations/'
                            .. deco.id
                code = t(url, ngx.HTTP_PUT, require("toolkit.json").encode(deco))
                if code >= 300 then
                    ngx.status = code
                    return
                end
            end

            local body
            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "shop-graphql",
                    "uri": "/graphql"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: hit - the schema is introspected from the upstream and the cost applied
--- request
POST /graphql
{"query":"query { products(first: 50) { nodes { name reviews(first: 20) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 52
X-RateLimit-Limit: 100000
X-RateLimit-Remaining: 99948



=== TEST 8: hit - one more nesting level, the quantifiers multiply
--- request
POST /graphql
{"query":"query { products(first: 50) { nodes { reviews(first: 20) { nodes { author { orders(first: 10) { nodes { id } } } } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 1052



=== TEST 9: hit - a quantifier passed as a variable is counted by default
--- request
POST /graphql
{"query":"query ($n: Int) { products(first: $n) { nodes { name } } }","variables":{"n":50}}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 2



=== TEST 10: a route not bound to a service has no decorations
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier"
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "uri": "/graphql-alt"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: hit - no service, so no decoration matches and the cost floors at 1
--- request
POST /graphql-alt
{"query":"query { products(first: 50) { nodes { name reviews(first: 20) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 1
--- error_log
the route is not bound to a service



=== TEST 12: update the service: disable resolve_variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier",
                            "resolve_variables": false
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: hit - with resolve_variables off the variable is invisible
--- request
POST /graphql
{"query":"query ($n: Int) { products(first: $n) { nodes { name } } }","variables":{"n":50}}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 1



=== TEST 14: hit - with it off the schema argument default is ignored too
--- request
POST /graphql
{"query":"query { topProducts { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 1



=== TEST 15: update the service: max_cost and a small quota
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 1000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier",
                            "max_cost": 100
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: hit - a query at exactly max_cost passes (the comparison is strict)
--- request
POST /graphql
{"query":"query { products(first: 98) { nodes { reviews(first: 5) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 100
X-RateLimit-Remaining: 900



=== TEST 17: hit - above max_cost: 403, and the quota is charged anyway
--- request
POST /graphql
{"query":"query { products(first: 150) { nodes { reviews(first: 2) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 403
--- response_headers
X-Graphql-Query-Cost: 152
X-RateLimit-Remaining: 848
--- response_body eval
qr/query cost 152 exceeds max_cost 100/



=== TEST 18: set service + route whose introspection endpoint cannot be reached
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/broken-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 1000,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/broken-graphql/graphql_cost_decorations/b1',
                 ngx.HTTP_PUT,
                 [[{"field_path": "Query.products", "mul_arguments": ["first"]}]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "broken-graphql",
                    "uri": "/graphql-broken"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 19: hit - a failed introspection rejects the request with 400
--- request
POST /graphql-broken
{"query":"query { products(first: 50) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
unexpected status 500
--- response_body eval
qr/failed to introspect the upstream graphql schema/



=== TEST 20: set service + route: complexity strategy, service without decorations
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/plain-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 1000,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "complexity",
                            "score_factor": 0.5
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "plain-graphql",
                    "uri": "/graphql-plain"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: hit - every node counts 1, then score_factor scales the total
--- request
POST /graphql-plain
{"query":"query { products(first: 50) { nodes { name id } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 3



=== TEST 22: update the service: max_cost with the default rejected_code (503)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 10,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier",
                            "max_cost": 20
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: hit - 403 wins over the rate limit rejection, quota charged anyway
--- request
POST /graphql
{"query":"query { products(first: 50) { nodes { reviews(first: 2) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 403
--- response_headers
X-Graphql-Query-Cost: 52
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 0
--- response_body eval
qr/query cost 52 exceeds max_cost 20/



=== TEST 24: update the service: same quota, no max_cost
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 10,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: hit - without max_cost the same query is the default rejection, 503
--- request
POST /graphql
{"query":"query { products(first: 50) { nodes { reviews(first: 2) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 503
--- response_headers
X-Graphql-Query-Cost: 52



=== TEST 26: reject a duplicate field_path introduced by PATCH
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t(
                '/apisix/admin/services/shop-graphql/graphql_cost_decorations/d3',
                ngx.HTTP_PATCH,
                [[{"field_path": "Query.products"}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/field_path Query.products is already decorated on this service by \[d1\]/



=== TEST 27: set service + route using an explicit introspection_endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/explicit-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier",
                            "introspection_endpoint": "http://127.0.0.1:1980/graphql-alt"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/explicit-graphql/graphql_cost_decorations/e1',
                 ngx.HTTP_PUT,
                 [[{"field_path": "Query.products",
                    "mul_arguments": ["first"], "add_value": 1}]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            -- the proxied path answers 500; only the explicit endpoint is usable,
            -- so a correct cost proves introspection did not follow the request path
            local body
            code, body = t('/apisix/admin/routes/5',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "explicit-graphql",
                    "uri": "/graphql-explicit"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 28: hit - introspection_endpoint is used instead of the request path
--- request
POST /graphql-explicit
{"query":"query { products(first: 9) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 500
--- response_headers
X-Graphql-Query-Cost: 2



=== TEST 29: a decoration change takes effect without a restart
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local function cost()
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:1984/graphql",
                    {
                        method = "POST",
                        headers = {["Content-Type"] = "application/json"},
                        body = '{"query":"query { products(first: 4) { nodes { name } } }"}',
                    })
                if not res then
                    return "request failed: " .. (err or "unknown")
                end
                return res.headers["X-Graphql-Query-Cost"]
            end

            local code = t('/apisix/admin/services/shop-graphql',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "key": "remote_addr",
                            "cost_strategy": "node_quantifier"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.say("before: ", cost())

            -- cost 1 -> 5, so the single decorated node costs 5 instead of 1
            code = t('/apisix/admin/services/shop-graphql/graphql_cost_decorations/d1',
                ngx.HTTP_PATCH, [[{"add_value": 5}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.5)
            ngx.say("after: ", cost())
        }
    }
--- response_body
before: 2
after: 6



=== TEST 30: set a prefix route so the request path reaches the introspection URL
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/6',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "shop-graphql",
                    "uri": "/gqlprefix/*"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 31: a CR/LF in the request path is escaped before it reaches the request line
--- request
POST /gqlprefix/a%0d%0aX-Injected:%20pwn
{"query":"query { products(first: 2) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log eval
qr/failed to request http:\/\/127\.0\.0\.1:1980\/gqlprefix\/a%0D%0AX-Injected: pwn/
--- no_error_log eval
qr/failed to request [^\n]*\r/



=== TEST 32: plugin metadata renames the rate limit headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- TEST 29 left cost at 5; put it back so the cost below is
            -- not a function of test order
            local code = t('/apisix/admin/services/shop-graphql/graphql_cost_decorations/d1',
                ngx.HTTP_PATCH, [[{"add_value": 1}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/plugin_metadata/graphql-limit-count',
                ngx.HTTP_PUT,
                [[{"limit_header": "X-Shop-Limit",
                   "remaining_header": "X-Shop-Remaining"}]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 33: hit - the renamed headers are the ones sent
--- request
POST /graphql
{"query":"query { products(first: 3) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Shop-Limit: 100000
X-Shop-Remaining: 99998
X-RateLimit-Limit:
X-RateLimit-Remaining:



=== TEST 34: decorations are not dumped as services by the control API
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            -- the control API crashes if it is asked before the services watcher
            -- has loaded, so give the fresh worker a moment
            local data
            for _ = 1, 10 do
                local httpc = require("resty.http").new()
                local res = httpc:request_uri("http://127.0.0.1:1984/v1/services")
                data = res and res.status == 200 and core.json.decode(res.body)
                if type(data) == "table" then
                    break
                end
                ngx.sleep(0.2)
            end

            if type(data) ~= "table" then
                ngx.say("failed to read /v1/services")
                return
            end
            local leaked, seen_service = 0, false
            for _, svc in ipairs(data) do
                if svc.value.field_path then
                    leaked = leaked + 1
                end
                if svc.value.id == "shop-graphql" then
                    seen_service = true
                end
            end
            ngx.say("leaked: ", leaked, ", service dumped: ", seen_service)
        }
    }
--- response_body
leaked: 0, service dumped: true



=== TEST 35: cost engine - inputs that must not reach the arithmetic
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "ProductConnection"}}},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {id = {type = "ID"}, name = {type = "String"}}},
                },
            }

            local decos = cost.build_index({
                {field_path = "Query.products", mul_arguments = {"first"}},
            })

            local function raw_cost(query)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost("complexity", operations, fragments,
                                       {decorations = decos, schema = schema})
            end

            -- a quantifier that is not a number is treated as absent: letting it
            -- reach the arithmetic would turn a client controlled value into a 500
            ngx.say(raw_cost([[query { products(first: "ten") { nodes { id } } }]]))
            ngx.say(raw_cost([[query { products(first: true) { nodes { id } } }]]))

            -- a numeric string still multiplies
            ngx.say(raw_cost([[query { products(first: "10") { nodes { id } } }]]))

            -- __typename is declared by no schema, and neither is an unknown field:
            -- both count as a plain undecorated node instead of failing the request
            ngx.say(raw_cost([[query { __typename products(first: 4) { nodes { id } } }]]))
            ngx.say(raw_cost([[query { products(first: 4) { nodes { id sku } } }]]))

            -- every operation in the document is costed and the most expensive one
            -- wins, so a cheap decoy operation cannot under charge the real one
            ngx.say(raw_cost([[
                query A { products(first: 2) { nodes { id } } }
                query B { products(first: 100) { nodes { id } } }
            ]]))

            -- the same field aliased twice is two nodes, each with its own quantifier
            ngx.say(raw_cost([[
                query {
                    cheap: products(first: 5) { nodes { id } }
                    expensive: products(first: 7) { nodes { id } }
                }
            ]]))
        }
    }
--- response_body
4
4
22
11
14
202
27



=== TEST 36: cost engine - a field_path deeper than <Type>.<field>
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {
                        products = {type = "ProductConnection"},
                        node = {type = "Product"},
                    }},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {
                        id = {type = "ID"},
                        reviews = {type = "ReviewConnection"},
                    }},
                    ReviewConnection = {fields = {nodes = {type = "Review"}}},
                    Review = {fields = {id = {type = "ID"}}},
                },
            }

            local function raw_cost(query, decos)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost("complexity", operations, fragments,
                                       {decorations = cost.build_index(decos),
                                        schema = schema})
            end

            -- three segments: Query -> products -> nodes
            ngx.say(raw_cost([[query { products(first: 4) { nodes { id } } }]], {
                {field_path = "Query.products.nodes", add_value = 9},
            }))

            -- four segments, with a quantifier on the deep node
            ngx.say(raw_cost([[
                query { products(first: 4) { nodes { reviews(first: 3) { nodes { id } } } } }
            ]], {
                {field_path = "Query.products", mul_arguments = {"first"}},
                {field_path = "Query.products.nodes.reviews", mul_arguments = {"first"},
                 add_value = 7},
            }))

            -- a deep path stays pinned to its chain: the `nodes` reached through
            -- Query.node.reviews is a different field selection and is not decorated
            ngx.say(raw_cost([[
                query {
                    products(first: 2) { nodes { id } }
                    node(id: "x") { reviews(first: 3) { nodes { id } } }
                }
            ]], {
                {field_path = "Query.products.nodes", add_value = 9},
            }))

            -- a shallow and a deep path can name the same field; they merge key by
            -- key with the longer one winning, whichever order they arrive in
            local shallow = {field_path = "Product.reviews", mul_arguments = {"first"},
                             add_value = 2}
            local deep = {field_path = "Query.products.nodes.reviews", add_value = 100}
            local overlap = [[
                query { products(first: 4) { nodes { reviews(first: 3) { nodes { id } } } } }
            ]]
            ngx.say(raw_cost(overlap, {shallow, deep}))
            ngx.say(raw_cost(overlap, {deep, shallow}))

            -- a stored row may carry the argument lists as empty arrays rather
            -- than omitting them. An empty list is a value like any other, so the
            -- more specific path clears the quantifier the shallow one set --
            -- still the same answer in either order, which is the point
            local shallow_row = {field_path = "Product.reviews", add_value = 2,
                                 mul_arguments = {"first"}, add_arguments = {}}
            local deep_row = {field_path = "Query.products.nodes.reviews",
                              add_value = 100, add_arguments = {},
                              mul_arguments = {}}
            ngx.say(raw_cost(overlap, {shallow_row, deep_row}))
            ngx.say(raw_cost(overlap, {deep_row, shallow_row}))
        }
    }
--- response_body
12
58
16
109
109
105
105



=== TEST 37: remove the plugin metadata so a repeated run starts clean
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/plugin_metadata/graphql-limit-count',
                           ngx.HTTP_DELETE)
            ngx.say("deleted: ", code)
        }
    }
--- request
GET /t
--- response_body
deleted: 200



=== TEST 38: hit - two operations without operationName: the dearer one is charged
--- request
POST /graphql-plain
{"query":"query A { products(first: 2) { nodes { id } } } query B { products(first: 100) { nodes { id name reviews(first: 5) { nodes { body } } } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 5



=== TEST 39: hit - operationName selects the operation that is actually executed
--- request
POST /graphql-plain
{"query":"query A { products(first: 2) { nodes { id } } } query B { products(first: 100) { nodes { id name reviews(first: 5) { nodes { body } } } } }","operationName":"A"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 3



=== TEST 40: hit - an operationName that matches nothing falls back to the dearest
--- request
POST /graphql-plain
{"query":"query A { products(first: 2) { nodes { id } } } query B { products(first: 100) { nodes { id name reviews(first: 5) { nodes { body } } } } }","operationName":"C"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 5



=== TEST 41: cost engine - an exponential fragment DAG is bounded, not costed
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {t = {type = "T"}}},
                    T = {fields = {a = {type = "String"}}},
                },
            }

            -- each fragment spreads the previous one twice, so the expansion is
            -- 2^n from a document that stays under a kilobyte
            local function dag(n)
                local parts = {"fragment f0 on T { a }"}
                for i = 1, n do
                    parts[#parts + 1] =
                        ("fragment f%d on T { ...f%d ...f%d }"):format(i, i - 1, i - 1)
                end
                parts[#parts + 1] = ("query { t { ...f%d } }"):format(n)
                return table.concat(parts, "\n")
            end

            local function raw_cost(query)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost("complexity", operations, fragments,
                                       {decorations = cost.build_index({}),
                                        schema = schema})
            end

            -- a modest DAG is still costed normally
            ngx.say(raw_cost(dag(10)))

            -- a large one is rejected instead of expanded, and quickly
            local started = os.clock()
            local raw, err = raw_cost(dag(24))
            local elapsed = os.clock() - started
            ngx.say("rejected: ", raw == nil, ", err: ", err)
            ngx.say("under a second: ", elapsed < 1)
        }
    }
--- response_body
1026
rejected: true, err: the query expands past 100000 selections
under a second: true



=== TEST 42: cost engine - a fragment type condition moves the type cursor
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            -- Query.node is an interface; `expensive` only exists on the concrete
            -- type, so the weight is only reachable through the type condition
            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {node = {type = "Node"}}},
                    Node = {fields = {id = {type = "ID"}}},
                    Product = {fields = {id = {type = "ID"},
                                         expensive = {type = "String"}}},
                },
            }
            local decos = cost.build_index({
                {field_path = "Product.expensive", add_value = 100},
            })

            local function raw_cost(query)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost("complexity", operations, fragments,
                                       {decorations = decos, schema = schema})
            end

            ngx.say(raw_cost([[query { node { ... on Product { expensive } } }]]))
            ngx.say(raw_cost([[
                query { node { ...pf } }
                fragment pf on Product { expensive }
            ]]))

            -- a condition the schema does not know leaves the cursor alone rather
            -- than losing it
            ngx.say(raw_cost([[query { node { ... on Unknown { id } } } ]]))
        }
    }
--- response_body
102
102
3



=== TEST 43: cost engine - a variable quantifier costs what the literal costs
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "PC"}}},
                    PC = {fields = {nodes = {type = "P"}}},
                    P = {fields = {id = {type = "ID"}}},
                },
            }
            local decos = cost.build_index({
                {field_path = "Query.products", mul_arguments = {"first"}},
            })

            local function raw_cost(query, strategy, variables)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost(strategy, operations, fragments,
                                       {decorations = decos, schema = schema,
                                        variables = variables,
                                        use_defaults = variables ~= nil})
            end

            -- moving the fan-out into a variable must not make the request cheaper
            local literal = [[query { products(first: 10000) { nodes { id } } }]]
            local var = [[query ($n: Int) { products(first: $n) { nodes { id } } }]]

            for _, strategy in ipairs({"complexity", "node_quantifier"}) do
                ngx.say(strategy, ": ",
                        raw_cost(literal, strategy, {}), " ",
                        raw_cost(var, strategy, {n = 10000}))
            end
        }
    }
--- response_body
complexity: 20002 20002
node_quantifier: 1 1



=== TEST 44: cost engine - a single token field_path is a type level rule
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "ProductConnection"}}},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {id = {type = "ID"}, name = {type = "String"}}},
                },
            }

            local query = [[query { products(first: 4) { nodes { id name } } }]]

            local function raw_cost(list)
                local ast = parse(query)
                local operations = {}
                for _, def in ipairs(ast.definitions) do
                    operations[#operations + 1] = def
                end

                return cost.query_cost("complexity", operations, {},
                                       {decorations = cost.build_index(list),
                                        schema = schema})
            end

            -- undecorated: operation + products + nodes + id + name
            ngx.say(raw_cost({}))

            -- `Query` names the root type, so it weights the operation node itself:
            -- (products = nodes(2) + 1 = 4) * 10 + 1
            ngx.say(raw_cost({{field_path = "Query", mul_value = 10}}))

            -- `Product` weights every field returning a Product, here `nodes`:
            -- nodes = (id + name) * 10 + 1 = 21 ; products = 22 ; op = 23
            ngx.say(raw_cost({{field_path = "Product", mul_value = 10}}))

            -- a type level rule and a field level rule can name the same node; the
            -- longer path is the more specific one and wins, so `nodes` multiplies
            -- by 2 rather than by 10
            ngx.say(raw_cost({
                {field_path = "Product", mul_value = 10},
                {field_path = "ProductConnection.nodes", mul_value = 2},
            }))

            -- and the answer does not depend on the order they are stored in
            ngx.say(raw_cost({
                {field_path = "ProductConnection.nodes", mul_value = 2},
                {field_path = "Product", mul_value = 10},
            }))

            -- a type nothing returns weights nothing
            ngx.say(raw_cost({{field_path = "Review", mul_value = 10}}))

            -- under node_quantifier only a node that carries a quantifier in this
            -- query is charged. The operation node never carries one, so a root
            -- type rule contributes nothing; a rule on a type reached through a
            -- quantified field still does.
            local function nq_cost(list)
                local ast = parse(query)
                local operations = {}
                for _, def in ipairs(ast.definitions) do
                    operations[#operations + 1] = def
                end

                return cost.query_cost("node_quantifier", operations, {},
                                       {decorations = cost.build_index(list),
                                        schema = schema})
            end

            ngx.say(nq_cost({{field_path = "Query", mul_value = 10}}))
            ngx.say(nq_cost({{field_path = "Query.products",
                              mul_arguments = {"first"}}}))
        }
    }
--- response_body
5
41
23
7
7
5
0
1



=== TEST 45: cost engine - a variable defaulted by the operation is not free
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "ProductConnection"}}},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {id = {type = "ID"}}},
                },
            }
            local decos = cost.build_index({
                {field_path = "Query.products", mul_arguments = {"first"}},
            })

            local function raw_cost(query, opts)
                local ast = parse(query)
                local operations = {}
                for _, def in ipairs(ast.definitions) do
                    operations[#operations + 1] = def
                end

                opts = opts or {}
                opts.decorations = decos
                opts.schema = schema
                return cost.query_cost("complexity", operations, {}, opts)
            end

            local defaulted =
                [[query Q($n: Int = 100) { products(first: $n) { nodes { id } } }]]

            -- the upstream executes this with first = 100, so it must not cost the
            -- same as an absent quantifier: products = nodes(2) * 100 + 1 ; op = 202
            ngx.say(raw_cost(defaulted, {use_defaults = true}))

            -- a supplied value wins over the default the operation declares
            ngx.say(raw_cost(defaulted, {use_defaults = true, variables = {n = 3}}))

            -- with resolve_variables off the variable stays invisible, default or not
            ngx.say(raw_cost(defaulted))

            -- a variable with no default and no supplied value is still absent
            ngx.say(raw_cost(
                [[query Q($n: Int) { products(first: $n) { nodes { id } } }]],
                {use_defaults = true}))
        }
    }
--- response_body
202
8
4
4



=== TEST 46: cost engine - variable defaults do not leak between operations
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "ProductConnection"}}},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {id = {type = "ID"}}},
                },
            }
            local decos = cost.build_index({
                {field_path = "Query.products", mul_arguments = {"first"}},
            })

            local function raw_cost(query)
                local ast = parse(query)
                local operations = {}
                for _, def in ipairs(ast.definitions) do
                    operations[#operations + 1] = def
                end

                return cost.query_cost("complexity", operations, {},
                                       {decorations = decos, schema = schema,
                                        use_defaults = true})
            end

            -- A declares $n = 2 and B declares none; B's `first: $n` is an
            -- undeclared variable and must not pick A's default up
            ngx.say(raw_cost([[
                query A($n: Int = 2) { products(first: $n) { nodes { id } } }
            ]]))
            ngx.say(raw_cost([[
                query B { products(first: $n) { nodes { id } } }
            ]]))
            ngx.say(raw_cost([[
                query A($n: Int = 2) { products(first: $n) { nodes { id } } }
                query B { products(first: $n) { nodes { id } } }
            ]]))
        }
    }
--- response_body
6
4
6



=== TEST 47: set a service whose decoration is a type level rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- drop the service first so a repeated run does not inherit
            -- decorations an earlier run left on it
            t('/apisix/admin/services/type-rule-svc', ngx.HTTP_DELETE)

            local code = t('/apisix/admin/services/type-rule-svc',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "complexity"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/type-rule-svc/graphql_cost_decorations/t1',
                 ngx.HTTP_PUT,
                 [[{"field_path": "Product", "mul_value": 10}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "type-rule-svc",
                    "uri": "/graphql"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 48: hit - the type level rule weights every field returning a Product
--- request
POST /graphql
{"query":"query { products(first: 2) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 14



=== TEST 49: set a service that weights a quantifier taken from the request
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            t('/apisix/admin/services/var-default-svc', ngx.HTTP_DELETE)

            local code = t('/apisix/admin/services/var-default-svc',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "complexity"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/var-default-svc/graphql_cost_decorations/v1',
                 ngx.HTTP_PUT,
                 [[{"field_path": "Query.products", "mul_arguments": ["first"]}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "var-default-svc",
                    "uri": "/graphql"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 50: hit - the literal quantifier, as the baseline
--- request
POST /graphql
{"query":"query { products(first: 50) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 103



=== TEST 51: hit - the same value declared as a variable default, no variables sent
--- request
POST /graphql
{"query":"query Q($n: Int = 50) { products(first: $n) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 103



=== TEST 52: hit - a supplied value wins over the default the operation declares
--- request
POST /graphql
{"query":"query Q($n: Int = 50) { products(first: $n) { nodes { name } } }","variables":{"n":2}}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 7



=== TEST 53: update the service: disable resolve_variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/var-default-svc',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "complexity",
                            "resolve_variables": false
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 54: hit - with resolve_variables off the declared default is invisible too
--- request
POST /graphql
{"query":"query Q($n: Int = 50) { products(first: $n) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 5



=== TEST 55: cost engine - destroy drops the per-worker schema cache
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.graphql-limit-count")
            local introspection = require("apisix.plugins.graphql-limit-count.introspection")

            -- reach the file-local caches through the upvalue chain rather than
            -- copying them, so this asserts the shipped state and not a replica
            local function upvalue(fn, name)
                local i = 1
                while true do
                    local key, value = debug.getupvalue(fn, i)
                    if not key then
                        return nil
                    end
                    if key == name then
                        return value
                    end
                    i = i + 1
                end
            end

            local function count(t)
                local n = 0
                for _ in pairs(t or {}) do
                    n = n + 1
                end
                return n
            end

            -- prime both caches the way a served request and a failed
            -- introspection leave them
            local schema_cache = upvalue(introspection.flush, "schema_cache")
            local failure_cache = upvalue(introspection.flush, "failure_cache")
            schema_cache["svc#1"] = {query_type = "Query", types = {}}
            failure_cache["svc#2"] = {err = "boom", expire_at = ngx.now() + 10}
            ngx.say("primed: ", count(schema_cache), " ", count(failure_cache))

            -- a plugin reload calls destroy() on the outgoing instance
            -- (apisix/plugin.lua), which must not leave a stale schema behind
            plugin.destroy()
            ngx.say("after destroy: ", count(upvalue(introspection.flush, "schema_cache")),
                    " ", count(upvalue(introspection.flush, "failure_cache")))
        }
    }
--- response_body
primed: 1 1
after destroy: 0 0



=== TEST 56: introspection - the request contributes no headers, the config does
--- config
    location /t {
        content_by_lua_block {
            local introspection =
                require("apisix.plugins.graphql-limit-count.introspection")

            local function upvalue(fn, name)
                local i = 1
                while true do
                    local key, value = debug.getupvalue(fn, i)
                    if not key then
                        return nil
                    end
                    if key == name then
                        return value
                    end
                    i = i + 1
                end
            end

            -- reached through the shipped module rather than copied, so this
            -- asserts what the introspection request actually sends
            local fetch_and_cache = upvalue(introspection.get, "fetch_and_cache")
            local fetch_schema = upvalue(fetch_and_cache, "fetch_schema")
            local build_headers = upvalue(fetch_schema, "build_headers")

            local function show(headers)
                local names = {}
                for name in pairs(headers) do
                    names[#names + 1] = name
                end
                table.sort(names)
                local out = {}
                for _, name in ipairs(names) do
                    out[#out + 1] = name .. "=" .. headers[name]
                end
                return table.concat(out, " ")
            end

            -- the caller sends credentials; none of them may reach the
            -- introspection request, because its result is cached per service and
            -- shared with every other caller
            ngx.req.set_header("Authorization", "Bearer caller-token")
            ngx.req.set_header("Cookie", "session=caller")

            ngx.say(show(build_headers({}, nil)))
            ngx.say(show(build_headers({}, "shop.example.com")))
            ngx.say(show(build_headers(
                {introspection_headers = {Authorization = "Bearer operator-token"}},
                "shop.example.com")))

            -- applied last, so the operator can override what the plugin sets
            ngx.say(show(build_headers(
                {introspection_headers = {["Content-Type"] = "application/graphql"}},
                nil)))
        }
    }
--- response_body
Content-Type=application/json
Content-Type=application/json Host=shop.example.com
Authorization=Bearer operator-token Content-Type=application/json Host=shop.example.com
Content-Type=application/graphql



=== TEST 57: set a service whose upstream needs credentials to introspect
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            t('/apisix/admin/services/guarded-svc', ngx.HTTP_DELETE)

            local code = t('/apisix/admin/services/guarded-svc',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "complexity"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/guarded-svc/graphql_cost_decorations/g1',
                 ngx.HTTP_PUT,
                 [[{"field_path": "Query.products", "mul_arguments": ["first"]}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "guarded-svc",
                    "uri": "/graphql-guarded"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 58: hit - the caller's own credentials do not introspect for it
--- request
POST /graphql-guarded
{"query":"query { products(first: 2) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
Authorization: Bearer operator-token
--- error_code: 400
--- response_body_like
.*failed to introspect the upstream graphql schema.*
--- error_log
unexpected status 401



=== TEST 59: set the operator's introspection credentials on the service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/guarded-svc',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000,
                            "time_window": 60,
                            "rejected_code": 429,
                            "key": "remote_addr",
                            "cost_strategy": "complexity",
                            "introspection_headers": {
                                "Authorization": "Bearer operator-token"
                            }
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 60: hit - with the operator's credentials the schema is introspected
--- request
POST /graphql-guarded
{"query":"query { products(first: 2) { nodes { name } } }"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-Graphql-Query-Cost: 7



=== TEST 61: cost engine - a quantifier that is not a count is treated as absent
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {products = {type = "ProductConnection"}}},
                    ProductConnection = {fields = {nodes = {type = "Product"}}},
                    Product = {fields = {id = {type = "ID"},
                                         reviews = {type = "ReviewConnection"}}},
                    ReviewConnection = {fields = {nodes = {type = "Review"}}},
                    Review = {fields = {id = {type = "ID"}}},
                },
            }
            local decos = cost.build_index({
                {field_path = "Query.products", mul_arguments = {"first"}},
                {field_path = "Product.reviews", mul_arguments = {"first"}},
            })

            local function raw_cost(first)
                local ast = parse("query { products(first: " .. first ..
                                  ") { nodes { reviews(first: 1000) " ..
                                  "{ nodes { id } } } } }")
                local operations = {}
                for _, def in ipairs(ast.definitions) do
                    operations[#operations + 1] = def
                end

                return cost.query_cost("complexity", operations, {},
                                       {decorations = decos, schema = schema})
            end

            -- the honest query, and the same one with the outer count omitted
            ngx.say(raw_cost("1000"))
            ngx.say(raw_cost("1"))

            -- a negative count is not a discount: it would flip the sign of the
            -- whole sub-tree and the floor of 1 would then charge the minimum for
            -- an arbitrarily expensive query
            ngx.say(raw_cost("-1"))
            ngx.say(raw_cost("-1000"))

            -- nor is anything else that is not a finite count
            ngx.say(raw_cost("1e400"))

            -- zero is a real count: the upstream resolves nothing under it
            ngx.say(raw_cost("0"))
        }
    }
--- response_body
2002002
2004
2004
2004
2004
2



=== TEST 62: cost engine - a fragment keeps matching once the index goes deep
--- config
    location /t {
        content_by_lua_block {
            local parse = require("graphql").parse
            local cost = require("apisix.plugins.graphql-limit-count.cost")

            local schema = {
                query_type = "Query",
                types = {
                    Query = {fields = {node = {type = "Node"}}},
                    Node = {fields = {id = {type = "ID"}}},
                    Product = {fields = {id = {type = "ID"},
                                         expensive = {type = "String"}}},
                    Unrelated = {fields = {x = {type = "ID"}}},
                },
            }

            local function raw_cost(query, list)
                local ast = parse(query)
                local fragments, operations = {}, {}
                for _, def in ipairs(ast.definitions) do
                    if def.kind == "fragmentDefinition" then
                        fragments[def.name.value] = def
                    else
                        operations[#operations + 1] = def
                    end
                end

                return cost.query_cost("complexity", operations, fragments,
                                       {decorations = cost.build_index(list),
                                        schema = schema})
            end

            local inline = [[query { node { ... on Product { expensive } } }]]
            local named = [[
                query { node { ...pf } }
                fragment pf on Product { expensive }
            ]]

            local weight = {field_path = "Product.expensive", add_value = 100}

            -- with only <type>.<field> rules the index stays flat and the weight is
            -- found by lookup; the deep walk has to reach the same answer, or an
            -- unrelated rule elsewhere on the service silently drops this one
            for _, query in ipairs({inline, named}) do
                ngx.say(raw_cost(query, {weight}), " ",
                        raw_cost(query, {weight,
                                         {field_path = "Query.node.id", add_value = 9}}),
                        " ",
                        raw_cost(query, {weight,
                                         {field_path = "Unrelated", add_value = 1}}))
            end

            -- and the deep path really is the one being taken: a three segment
            -- rule reaching past the fragment still applies, so the reseed adds
            -- the fragment's type without dropping the inherited candidates
            ngx.say(raw_cost(
                [[query { node { id ... on Product { expensive } } }]],
                {weight, {field_path = "Query.node.id", add_value = 9}}))

            -- a condition the schema does not know still leaves the cursor alone
            ngx.say(raw_cost([[query { node { ... on Unknown { id } } }]],
                             {weight, {field_path = "Unrelated", add_value = 1}}))
        }
    }
--- response_body
102 102 102
102 102 102
111
3



=== TEST 63: schema - introspection_headers is encrypted like any other credential
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.graphql-limit-count")

            local fields = {}
            for _, name in ipairs(plugin.schema.encrypt_fields or {}) do
                fields[name] = true
            end

            -- the list came with limit-count's schema; the introspection
            -- credentials are this plugin's own and have to join it
            ngx.say("redis_password: ", fields.redis_password and "yes" or "no")
            ngx.say("introspection_headers: ",
                    fields.introspection_headers and "yes" or "no")
        }
    }
--- response_body
redis_password: yes
introspection_headers: yes



=== TEST 64: introspection - the query asks for enough wrapper depth to name a type
--- config
    location /t {
        content_by_lua_block {
            local introspection =
                require("apisix.plugins.graphql-limit-count.introspection")

            local function upvalue(fn, name)
                local i = 1
                while true do
                    local key, value = debug.getupvalue(fn, i)
                    if not key then
                        return nil
                    end
                    if key == name then
                        return value
                    end
                    i = i + 1
                end
            end

            local fetch_and_cache = upvalue(introspection.get, "fetch_and_cache")
            local fetch_schema = upvalue(fetch_and_cache, "fetch_schema")
            local query = upvalue(fetch_schema, "INTROSPECTION_QUERY")
            local build_index = upvalue(fetch_schema, "build_index")

            -- The unwrapping can descend forever, but it can only descend through
            -- links the query asked for: an upstream answers exactly as deep as it
            -- was asked and no deeper, so a chain longer than that comes back with
            -- no name and every decoration under the field is silently missed.
            -- [[Product!]!]! is already five wrappers.
            local _, links = query:gsub("ofType", "")
            ngx.say("ofType links in the query: ", links)

            local function wrap(depth)
                local ref = {kind = "OBJECT", name = "Product"}
                for i = 1, depth do
                    ref = {kind = (i % 2 == 1) and "NON_NULL" or "LIST",
                           name = nil, ofType = ref}
                end
                return ref
            end

            -- what an upstream truncated to the depth the query expresses looks
            -- like: the deepest link the query did not ask for is simply absent
            local function truncate(ref, budget)
                if budget == 0 then
                    return {kind = ref.kind, name = ref.name}
                end
                if not ref.ofType then
                    return {kind = ref.kind, name = ref.name}
                end
                return {kind = ref.kind, name = ref.name,
                        ofType = truncate(ref.ofType, budget - 1)}
            end

            local function resolved(depth)
                local index = build_index({
                    __schema = {
                        queryType = {name = "Query"},
                        types = {
                            {kind = "OBJECT", name = "Query",
                             fields = {{name = "grid",
                                        type = truncate(wrap(depth), links),
                                        args = {}}}},
                        },
                    },
                })
                return index.types.Query.fields.grid.type or "unresolved"
            end

            for _, depth in ipairs({1, 3, 5}) do
                ngx.say(depth, " wrappers -> ", resolved(depth))
            end
        }
    }
--- response_body
ofType links in the query: 7
1 wrappers -> Product
3 wrappers -> Product
5 wrappers -> Product



=== TEST 65: two services sharing one introspection endpoint keep separate schemas
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Both point at the same guarded URL, but only one is given the
            -- credentials for it. Keying the cache by the endpoint would let
            -- whichever service warms the worker answer for the other.
            local services = {
                {id = "shared-a", uri = "/graphql-shared-a",
                 token = "Bearer operator-token"},
                {id = "shared-b", uri = "/graphql-shared-b",
                 token = "Bearer wrong-token"},
            }

            for _, svc in ipairs(services) do
                t('/apisix/admin/services/' .. svc.id, ngx.HTTP_DELETE)

                local body = string.format([[{
                    "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"},
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 100000, "time_window": 60,
                            "rejected_code": 429, "key": "remote_addr",
                            "cost_strategy": "complexity",
                            "introspection_endpoint": "http://127.0.0.1:1980/graphql-guarded",
                            "introspection_headers": {"Authorization": "%s"}
                        }
                    }
                }]], svc.token)

                local code = t('/apisix/admin/services/' .. svc.id, ngx.HTTP_PUT, body)
                if code >= 300 then
                    ngx.status = code
                    return
                end

                code = t('/apisix/admin/services/' .. svc.id ..
                         '/graphql_cost_decorations/d', ngx.HTTP_PUT,
                         [[{"field_path": "Query.products", "mul_arguments": ["first"]}]])
                if code >= 300 then
                    ngx.status = code
                    return
                end

                code = t('/apisix/admin/routes/' .. svc.id, ngx.HTTP_PUT,
                         string.format([[{"service_id": "%s", "uri": "%s"}]],
                                       svc.id, svc.uri))
                if code >= 300 then
                    ngx.status = code
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 66: one worker, both services: neither inherits the other's schema
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")

            -- Both requests are made inside one block so they share a worker, and
            -- therefore the schema cache. Test::Nginx starts a fresh server per
            -- block, so two separate blocks could never observe the leak.
            local function hit(path)
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984" .. path, {
                    method = "POST",
                    headers = {["Content-Type"] = "application/json"},
                    body = '{"query":"query { products(first: 2) { nodes { name } } }"}',
                })
                if not res then
                    return "error: " .. err
                end
                return res.status .. " " ..
                       (res.headers["X-Graphql-Query-Cost"] or "no-cost-header")
            end

            -- the one holding the credentials warms the cache first
            ngx.say("with credentials:    ", hit("/graphql-shared-a"))
            -- the one without must still be refused, not answered from that entry
            ngx.say("without credentials: ", hit("/graphql-shared-b"))
            -- and the first must keep working afterwards
            ngx.say("with credentials:    ", hit("/graphql-shared-a"))
        }
    }
--- request
GET /t
--- response_body
with credentials:    200 7
without credentials: 400 no-cost-header
with credentials:    200 7
--- error_log
unexpected status 401



=== TEST 67: a decoration id colliding with a service id does not answer for it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            -- The services watcher carries the decorations too, and the health
            -- check lookup only compares ids, so a decoration named after a
            -- service could answer for it and report no checker. It cannot: the
            -- runtime id of a decoration is its whole sub path
            -- (`<service>/graphql_cost_decorations/<id>`), which no service id can
            -- be, since those admit no slash. This pins that -- the owner is named
            -- so the decoration is reached first if it ever could match.
            for _, id in ipairs({"aaa-owner", "hc-svc"}) do
                t('/apisix/admin/services/' .. id, ngx.HTTP_DELETE)
            end

            local code = t('/apisix/admin/services/aaa-owner', ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            ngx.say("owner: ", code)

            code = t('/apisix/admin/services/aaa-owner/graphql_cost_decorations/hc-svc',
                     ngx.HTTP_PUT, [[{"field_path": "Query.products"}]])
            ngx.say("colliding decoration: ", code)

            code = t('/apisix/admin/services/hc-svc', ngx.HTTP_PUT, [[{
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin",
                    "checks": {
                        "active": {
                            "http_path": "/status",
                            "healthy": {"interval": 1, "successes": 1},
                            "unhealthy": {"interval": 1, "http_failures": 1}
                        }
                    }
                }
            }]])
            ngx.say("service with a checker: ", code)

            code = t('/apisix/admin/routes/hc-route', ngx.HTTP_PUT,
                     [[{"service_id": "hc-svc", "uri": "/hc-probe"}]])
            ngx.say("route: ", code)

            -- the checker is created lazily on the first request through it
            local httpc = http.new()
            httpc:request_uri("http://127.0.0.1:1984/hc-probe")

            local res
            for _ = 1, 10 do
                httpc = http.new()
                res = httpc:request_uri(
                    "http://127.0.0.1:1984/v1/healthcheck/services/hc-svc")
                if res and res.status == 200 then
                    break
                end
                ngx.sleep(0.1)
            end

            ngx.say("healthcheck: ", res and res.status,
                    " ", res and res.body and res.body:find("hc%-svc") and "names the service"
                        or (res and res.body or ""))

            for _, id in ipairs({"aaa-owner", "hc-svc"}) do
                t('/apisix/admin/routes/hc-route', ngx.HTTP_DELETE)
                t('/apisix/admin/services/' .. id, ngx.HTTP_DELETE)
            end
        }
    }
--- request
GET /t
--- response_body
owner: 201
colliding decoration: 201
service with a checker: 201
route: 201
healthcheck: 200 names the service
