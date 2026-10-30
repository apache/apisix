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
log_level('info');

# Shared config: avoids an nginx restart, and the etcd re-sync, between blocks.
my $config = <<'_EOC_';
    location /parse_ok {
        content_by_lua_block {
            local http_rule = require("apisix.plugins.grpc-transcode.http_rule")

            local cases = {
                "/api/v1/items",
                "/api/v1/items/{id}",
                "/api/v1/items/{item_id}/notes/{note_id}",
                "/v1/{name=shelves/*/books/*}",
                "/v1/{path=**}",
                "/v1/items/*",
                "/v1/{id}:cancel",
                "/v1/{name=shelves/**}",
                "/v1/a.b/{id}",
            }

            for _, tmpl in ipairs(cases) do
                local regex, vars = http_rule.parse_path_template(tmpl)
                ngx.say(tmpl, " -> ", regex, " vars=", #vars)
            end

            local _, nested = http_rule.parse_path_template("/v1/{user.id}/x")
            ngx.say("nested field path: ", table.concat(nested[1], "|"))

            -- `**` is zero or more segments.
            local proto_fake_file =
                require("apisix.plugins.grpc-transcode.proto").proto_fake_file
            local rules = http_rule.build({[proto_fake_file] = {index = {["t.S"] = {
                M = {options = {http = {pattern = "get", get = "/v1/{path=**}"}}},
            }}}})
            for _, uri in ipairs({"/v1", "/v1/", "/v1/a", "/v1/a/b"}) do
                local rule, params = http_rule.match(rules, "GET", uri)
                ngx.say(uri, " -> ", rule and "match" or "no match",
                        " path=", params and string.format("%q", params.path) or "-")
            end
        }
    }

    location /parse_reject {
        content_by_lua_block {
            local http_rule = require("apisix.plugins.grpc-transcode.http_rule")

            local cases = {
                "v1/no-leading-slash",
                "/v1/{unbalanced",
                "/v1/{a={b}}",
                "/v1/{}",
                "/v1/{=*}",
                "/v1/{a-b}",
                "/v1/{a..b}",
                "/v1/**/more",
                "/v1/{a=**}/more",
            }

            for _, tmpl in ipairs(cases) do
                local _, err = http_rule.parse_path_template(tmpl)
                ngx.say(tmpl, " -> ", err)
            end
        }
    }

    location /verb_precedence {
        content_by_lua_block {
            local http_rule = require("apisix.plugins.grpc-transcode.http_rule")
            local proto_fake_file =
                require("apisix.plugins.grpc-transcode.proto").proto_fake_file

            -- Each template takes only the uri carrying its own verb.
            local index = {["t.S"] = {
                Plain  = {options = {http = {pattern = "get", get = "/v1/{id}"}}},
                Cancel = {options = {http = {pattern = "get", get = "/v1/{id}:cancel"}}},
            }}
            local rules = http_rule.build({[proto_fake_file] = {index = index}})

            local rule = http_rule.match(rules, "GET", "/v1/42:cancel")
            ngx.say("with verb: ", rule and rule.method)
            rule = http_rule.match(rules, "GET", "/v1/42")
            ngx.say("without verb: ", rule and rule.method)

            -- A custom pattern names no HTTP method, so it yields no rule.
            local custom_only = {["t.S"] = {
                R = {options = {http = {pattern = "custom",
                                        custom = {kind = "REPORT",
                                                  path = "/v1/{id}:report"}}}},
            }}
            local built = http_rule.build({[proto_fake_file] = {index = custom_only}})
            ngx.say("custom only: ", built and "built a table" or "no rules")
        }
    }

    location /setup {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local content = t.read_file("t/grpc_server_example/http_binding.pb")
            local code = t.test('/apisix/admin/protos/1', ngx.HTTP_PUT,
                                json.encode({content = ngx.encode_base64(content)}))
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to set the proto")
                return
            end

            local upstream = [[
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
            ]]

            local routes = {
                -- one route for the whole annotated service
                {"1", [[{
                    "uri": "/api/v1/*",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "use_http_annotations": true
                        }
                    },]] .. upstream .. "}"},
                -- legacy service/method route
                {"3", [[{
                    "uri": "/legacy",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "http_binding.ItemService",
                            "method": "GetItem"
                        }
                    },]] .. upstream .. "}"},
                -- a uri rewritten before this plugin runs
                {"4", [[{
                    "uri": "/shop/*",
                    "plugins": {
                        "proxy-rewrite": {
                            "regex_uri": ["^/shop/(.*)", "/api/v1/items/$1"]
                        },
                        "grpc-transcode": {
                            "proto_id": "1",
                            "use_http_annotations": true
                        }
                    },]] .. upstream .. "}"},
            }

            for _, route in ipairs(routes) do
                local c, body = t.test('/apisix/admin/routes/' .. route[1],
                                       ngx.HTTP_PUT, route[2])
                if c >= 300 then
                    ngx.status = c
                    ngx.say("failed to set route ", route[1], ": ", body)
                    return
                end
            end

            -- Wait for the watcher to deliver the write: 404 means the route
            -- has not landed, 503 means the proto has not.
            local http = require("resty.http")
            local url = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v1/items/ready"
            local ready
            for _ = 1, 100 do
                local res = http.new():request_uri(url, {keepalive = false})
                if res and res.status == 200 then
                    ready = true
                    break
                end
                ngx.sleep(0.05)
            end

            if not ready then
                ngx.say("routes did not become available")
                return
            end

            ngx.say("passed")
        }
    }

    location /schema_requires_method {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/bad",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:10051": 1
                        }
                    }
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }

    location /replace_proto {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            -- echo.pb has no annotation, so nothing is left to route with.
            local content = t.read_file("t/grpc_server_example/echo.pb")
            local code = t.test('/apisix/admin/protos/1', ngx.HTTP_PUT,
                                json.encode({content = ngx.encode_base64(content)}))
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to update the proto")
                return
            end

            -- Poll so a slow watcher shows up as a timeout, not a stale 200.
            local http = require("resty.http")
            local url = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v1/items/42"
            local status
            for _ = 1, 100 do
                local res = http.new():request_uri(url, {keepalive = false})
                status = res and res.status
                if status ~= 200 then
                    break
                end
                ngx.sleep(0.05)
            end

            ngx.say("after update: ", status)
        }
    }
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: parse path templates
--- request
GET /parse_ok
--- response_body
/api/v1/items -> ^/api/v1/items$ vars=0
/api/v1/items/{id} -> ^/api/v1/items/([^/]+)$ vars=1
/api/v1/items/{item_id}/notes/{note_id} -> ^/api/v1/items/([^/]+)/notes/([^/]+)$ vars=2
/v1/{name=shelves/*/books/*} -> ^/v1/(shelves/[^/]+/books/[^/]+)$ vars=1
/v1/{path=**} -> ^/v1(?:/(.*))?$ vars=1
/v1/items/* -> ^/v1/items/[^/]+$ vars=0
/v1/{id}:cancel -> ^/v1/([^/]+)$ vars=1
/v1/{name=shelves/**} -> ^/v1/(shelves(?:/.*)?)$ vars=1
/v1/a.b/{id} -> ^/v1/a\.b/([^/]+)$ vars=1
nested field path: user|id
/v1 -> match path=""
/v1/ -> match path=""
/v1/a -> match path="a"
/v1/a/b -> match path="a/b"



=== TEST 2: reject malformed path templates
--- request
GET /parse_reject
--- response_body
v1/no-leading-slash -> path template must start with '/'
/v1/{unbalanced -> unbalanced '{' in path template
/v1/{a={b}} -> nested variable in path template
/v1/{} -> invalid field path in path template
/v1/{=*} -> invalid field path in path template
/v1/{a-b} -> invalid field path in path template
/v1/{a..b} -> invalid field path in path template
/v1/**/more -> '**' must be the last segment in a path template
/v1/{a=**}/more -> '**' must be the last segment in a path template



=== TEST 3: verb binding vs bare variable
--- request
GET /verb_precedence
--- response_body
with verb: Cancel
without verb: Plain
custom only: no rules



=== TEST 4: set proto(id: 1) and routes
--- request
GET /setup
--- response_body
passed
--- wait: 1



=== TEST 5: hit route with path param
--- request
GET /api/v1/items/42
--- response_body chomp
{"message":"GetItem id=42"}



=== TEST 6: hit route by query string
--- request
GET /api/v1/items?page_size=5
--- response_body chomp
{"message":"ListItems page_size=5"}



=== TEST 7: static segment wins over variable
--- request
GET /api/v1/items/active
--- response_body chomp
{"message":"GetActiveItem"}



=== TEST 8: multiple path params
--- request
GET /api/v1/items/i1/notes/n9
--- response_body chomp
{"message":"GetItemNote item_id=i1 note_id=n9"}



=== TEST 9: additional_bindings
--- request
GET /api/v1/i/i2/n/n3
--- response_body chomp
{"message":"GetItemNote item_id=i2 note_id=n3"}



=== TEST 10: body: field wraps the payload
--- request
POST /api/v1/items
{"id":"9","title":"widget","amount":50}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"CreateItem id=9 title=widget amount=50 request_id="}



=== TEST 11: path wins over query param
--- request
GET /api/v1/items/42?id=99
--- response_body chomp
{"message":"GetItem id=42"}



=== TEST 12: path wins over body field
--- request
PATCH /api/v1/items/42
{"id":"victim","title":"x"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"UpdateItem id=42 title=x"}



=== TEST 13: path wins over nested body field
--- request
PUT /api/v1/items/42
{"id":"victim","title":"x"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"ReplaceItem id=42 title=x"}



=== TEST 14: path wins over body and query
--- request
PATCH /api/v1/items/42?id=victim2
{"id":"victim","title":"x"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"UpdateItem id=42 title=x"}



=== TEST 15: captured value is not double decoded
--- request
GET /api/v1/items/a%2520b
--- response_body chomp
{"message":"GetItem id=a%20b"}



=== TEST 16: escaped separator spans two segments
--- request
GET /api/v1/items/a%2Fb
--- error_code: 404
--- error_log
no google.api.http binding matches GET /api/v1/items/a/b



=== TEST 17: unmatched path
--- request
GET /api/v1/nonexistent
--- error_code: 404
--- error_log
no google.api.http binding matches GET /api/v1/nonexistent



=== TEST 18: wrong method
--- request
POST /api/v1/items/42
--- error_code: 405
--- response_headers
Allow: DELETE, GET, PATCH, PUT
--- error_log
no google.api.http binding matches POST /api/v1/items/42



=== TEST 19: method without annotation
--- request
GET /api/v1/unannotated
--- error_code: 404



=== TEST 20: proxy-rewrite uri is matched
--- request
GET /shop/77
--- response_body chomp
{"message":"GetItem id=77"}



=== TEST 21: explicit service/method still works
--- request
GET /legacy?id=legacy-7
--- response_body chomp
{"message":"GetItem id=legacy-7"}



=== TEST 22: template without verb ignores verb uri
--- request
GET /api/v1/items/42:cancel
--- error_code: 405
--- response_headers
Allow: POST
--- error_log
no google.api.http binding matches GET /api/v1/items/42:cancel



=== TEST 23: verb binding strips the verb
--- request
POST /api/v1/items/42:cancel
--- response_body chomp
{"message":"CancelItem id=42 title="}



=== TEST 24: unknown verb
--- request
GET /api/v1/items/42:report
--- error_code: 404
--- error_log
no google.api.http binding matches GET /api/v1/items/42:report



=== TEST 25: colon outside the final segment
--- request
GET /api/v1/items/a:b/x
--- error_code: 404



=== TEST 26: undecodable json body
--- request
PATCH /api/v1/items/42
{"title": broken
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
failed to decode the request body as JSON



=== TEST 27: omitted body is not read
--- request
POST /api/v1/items/42:cancel
{"title":"injected"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"CancelItem id=42 title="}



=== TEST 28: omitted body reads query
--- request
POST /api/v1/items/42:cancel?title=fromquery
{"title":"injected"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"CancelItem id=42 title=fromquery"}



=== TEST 29: body: field reads siblings from query
--- request
POST /api/v1/items?request_id=r1
{"id":"9","title":"widget","amount":50}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"message":"CreateItem id=9 title=widget amount=50 request_id=r1"}



=== TEST 30: delete binding
--- request
DELETE /api/v1/items/42
--- response_body chomp
{"message":"DeleteItem id=42"}



=== TEST 31: custom pattern is not routable
--- request
POST /api/v1/items/42:report
--- error_code: 404



=== TEST 32: service and method required without the flag
--- request
GET /schema_requires_method
--- error_code: 400
--- response_body eval
qr/property \\"(service|method)\\" is required/



=== TEST 33: replacing the proto rebuilds the table
--- request
GET /replace_proto
--- response_body
after update: 503
--- error_log
no google.api.http annotation found in the proto
