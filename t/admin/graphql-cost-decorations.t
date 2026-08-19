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
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: create a decoration on a service that does not exist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d1',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.products", "mul_arguments": ["first"]}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body
{"error_msg":"service not found"}



=== TEST 2: add the service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
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



=== TEST 3: create a decoration, service_id is taken from the path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d1',
                ngx.HTTP_PUT,
                [[{
                    "field_path": "Query.products",
                    "mul_arguments": ["first"],
                    "add_value": 1
                }]],
                [[{
                    "key": "/apisix/services/shop/graphql_cost_decorations/d1",
                    "value": {
                        "id": "d1",
                        "service_id": "shop",
                        "field_path": "Query.products",
                        "mul_arguments": ["first"],
                        "add_value": 1
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: reject a service_id that contradicts the path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d2',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.orders", "service_id": "blog"}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong service_id, it is taken from the path"}



=== TEST 5: reject a duplicate field_path on the same service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d2',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.products", "add_value": 5}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/"error_msg":"field_path Query.products is already decorated on this service by \[d1\]"/



=== TEST 6: reject a malformed field_path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d2',
                ngx.HTTP_PUT,
                [[{"field_path": "9Query.products"}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/field_path/



=== TEST 7: create a second decoration with POST, the id is generated
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, raw = t('/apisix/admin/services/shop/graphql_cost_decorations',
                ngx.HTTP_POST,
                [[{"field_path": "Product.reviews", "mul_arguments": ["first"]}]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = require("toolkit.json").decode(raw)
            -- the id is generated by etcd, so only assert the parent dir
            ngx.say(data.value.service_id, " ", data.value.field_path,
                    " ", (data.key:gsub("/[^/]+$", "")))
        }
    }
--- request
GET /t
--- response_body
shop Product.reviews /apisix/services/shop/graphql_cost_decorations



=== TEST 8: list the decorations of the service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, raw = t('/apisix/admin/services/shop/graphql_cost_decorations',
                ngx.HTTP_GET)

            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = require("toolkit.json").decode(raw)
            local paths = {}
            for _, item in ipairs(data.list) do
                table.insert(paths, item.value.field_path)
            end
            table.sort(paths)
            ngx.say(data.total, " ", table.concat(paths, ","))
        }
    }
--- request
GET /t
--- response_body
2 Product.reviews,Query.products



=== TEST 9: patch a single decoration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, raw = t('/apisix/admin/services/shop/graphql_cost_decorations/d1',
                ngx.HTTP_PATCH,
                [[{"add_value": 7}]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = require("toolkit.json").decode(raw)
            ngx.say(data.value.add_value, " ", data.value.field_path,
                    " ", data.value.service_id)
        }
    }
--- request
GET /t
--- response_body
7 Query.products shop



=== TEST 10: service_id can not be patched
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop/graphql_cost_decorations/d1',
                ngx.HTTP_PATCH,
                [[{"service_id": "blog"}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"service_id can not be patched"}



=== TEST 11: a decoration of another service is not listed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/services/shop2',
                ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/shop2/graphql_cost_decorations/d9',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.posts"}]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local _, _, raw = t('/apisix/admin/services/shop/graphql_cost_decorations',
                ngx.HTTP_GET)
            local data = require("toolkit.json").decode(raw)
            ngx.say(data.total)
        }
    }
--- request
GET /t
--- response_body
2



=== TEST 12: delete a single decoration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/services/shop/graphql_cost_decorations/d1',
                ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return
            end

            local _, _, raw = t('/apisix/admin/services/shop/graphql_cost_decorations',
                ngx.HTTP_GET)
            local data = require("toolkit.json").decode(raw)
            ngx.say(data.total)
        }
    }
--- request
GET /t
--- response_body
1



=== TEST 13: deleting the service reclaims its decorations
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/services/shop', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return
            end

            local code2 = t('/apisix/admin/services/shop/graphql_cost_decorations',
                ngx.HTTP_GET)
            ngx.say(code2)

            -- the other service keeps its own
            local _, _, raw = t('/apisix/admin/services/shop2/graphql_cost_decorations',
                ngx.HTTP_GET)
            local data = require("toolkit.json").decode(raw)
            ngx.say(data.total)
        }
    }
--- request
GET /t
--- response_body
404
1



=== TEST 14: a rejected service delete leaves the decorations intact
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/shop3',
                ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/services/shop3/graphql_cost_decorations/k1',
                ngx.HTTP_PUT, [[{"field_path": "Query.keep"}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            -- a route referencing the service makes delete_checker reject
            code = t('/apisix/admin/routes/900',
                ngx.HTTP_PUT, [[{"service_id": "shop3", "uri": "/keep"}]])
            if code >= 300 then
                ngx.status = code
                return
            end

            local body
            code, body = t('/apisix/admin/services/shop3', ngx.HTTP_DELETE)
            ngx.say("delete: ", code)

            -- the decorations of the surviving service must still be there
            local _, _, raw = t('/apisix/admin/services/shop3/graphql_cost_decorations',
                ngx.HTTP_GET)
            local data = require("toolkit.json").decode(raw)
            ngx.say("decorations: ", data.total)
        }
    }
--- request
GET /t
--- response_body
delete: 400
decorations: 1



=== TEST 15: reject negative decoration constants
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/shop2/graphql_cost_decorations/n1',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.neg", "add_value": -1}]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/add_value\W+validation failed/



=== TEST 16: decorations do not leak into the services list
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, _, raw = t('/apisix/admin/services', ngx.HTTP_GET)
            local data = require("toolkit.json").decode(raw)

            -- a decoration is recognisable by its field_path; not asserting the
            -- total keeps this independent of whatever else is in etcd
            local leaked, seen = 0, {}
            for _, item in ipairs(data.list) do
                if item.value.field_path then
                    leaked = leaked + 1
                end
                seen[item.value.id] = true
            end
            ngx.say("leaked: ", leaked)
            ngx.say("shop2: ", seen["shop2"] == true, ", shop3: ", seen["shop3"] == true)
        }
    }
--- request
GET /t
--- response_body
leaked: 0
shop2: true, shop3: true



=== TEST 17: an invalid PUT for an absent service id keeps the decorations
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")

            -- a previous run of this file may have left the service behind, which
            -- would turn the create below into an update
            core.etcd.delete("/services/orphan-svc")

            -- seed the state a failed delete-side reclaim leaves behind: an id with
            -- decorations but no service
            local res, err = core.etcd.set(
                "/services/orphan-svc/graphql_cost_decorations/o1",
                {id = "o1", service_id = "orphan-svc", field_path = "Query.kept"})
            if not res then
                ngx.say("seed failed: ", err)
                return
            end

            -- an invalid create for that id must not destroy them on its way out
            local code = t('/apisix/admin/services/orphan-svc',
                ngx.HTTP_PUT, [[{"upstream": {"type": "not-a-type"}}]])
            ngx.say("invalid put: ", code)

            res = core.etcd.get("/services/orphan-svc/graphql_cost_decorations", true)
            ngx.say("after invalid put: ", res.body.list and #res.body.list or 0)

            -- a valid create reclaims them, so the new service cannot inherit
            code = t('/apisix/admin/services/orphan-svc',
                ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            ngx.say("valid put: ", code)

            res = core.etcd.get("/services/orphan-svc/graphql_cost_decorations", true)
            ngx.say("after valid put: ", res.body.list and #res.body.list or 0)
        }
    }
--- request
GET /t
--- response_body
invalid put: 400
after invalid put: 1
valid put: 201
after valid put: 0



=== TEST 18: accept a field_path deeper than <Type>.<field>
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/deep-svc',
                ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            ngx.say("service: ", code)

            -- four segments: a type, then the chain of fields it is pinned to
            code = t('/apisix/admin/services/deep-svc/graphql_cost_decorations/deep',
                ngx.HTTP_PUT,
                [[{"field_path": "Query.products.nodes.reviews", "add_value": 7}]])
            ngx.say("deep path: ", code)

            -- a dot alone is still not a path
            code = t('/apisix/admin/services/deep-svc/graphql_cost_decorations/bad1',
                ngx.HTTP_PUT, [[{"field_path": "Query."}]])
            ngx.say("trailing dot: ", code)

            code = t('/apisix/admin/services/deep-svc/graphql_cost_decorations/bad2',
                ngx.HTTP_PUT, [[{"field_path": "Query..products"}]])
            ngx.say("empty segment: ", code)

            code = t('/apisix/admin/services/deep-svc', ngx.HTTP_DELETE)
            ngx.say("cleanup: ", code)
        }
    }
--- request
GET /t
--- response_body
service: 201
deep path: 201
trailing dot: 400
empty segment: 400
cleanup: 200



=== TEST 19: accept a single token field_path as a type level rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/services/type-level-svc',
                ngx.HTTP_PUT,
                [[{"upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            ngx.say("service: ", code)

            -- a single token names a type, so the rule applies to every field
            -- returning it; the root type names the operation node itself
            code = t('/apisix/admin/services/type-level-svc/graphql_cost_decorations/t1',
                ngx.HTTP_PUT, [[{"field_path": "Product", "mul_value": 10}]])
            ngx.say("object type: ", code)

            code = t('/apisix/admin/services/type-level-svc/graphql_cost_decorations/t2',
                ngx.HTTP_PUT, [[{"field_path": "Query", "mul_value": 2}]])
            ngx.say("root type: ", code)

            -- a type level rule and a field level rule on the same type coexist
            code = t('/apisix/admin/services/type-level-svc/graphql_cost_decorations/t3',
                ngx.HTTP_PUT, [[{"field_path": "Product.reviews", "add_value": 5}]])
            ngx.say("field on the same type: ", code)

            -- but a second rule on the same type is still a duplicate
            code = t('/apisix/admin/services/type-level-svc/graphql_cost_decorations/t4',
                ngx.HTTP_PUT, [[{"field_path": "Product", "add_value": 1}]])
            ngx.say("duplicate type: ", code)

            -- a leading digit is not a GraphQL name
            code = t('/apisix/admin/services/type-level-svc/graphql_cost_decorations/bad',
                ngx.HTTP_PUT, [[{"field_path": "9Product"}]])
            ngx.say("leading digit: ", code)

            code = t('/apisix/admin/services/type-level-svc', ngx.HTTP_DELETE)
            ngx.say("cleanup: ", code)
        }
    }
--- request
GET /t
--- response_body
service: 201
object type: 201
root type: 201
field on the same type: 201
duplicate type: 400
leading digit: 400
cleanup: 200
