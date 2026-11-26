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


BEGIN {
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();


my $resp_file = 't/assets/embeddings.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $embeddings = do { local $/; <$fh> };
close($fh);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 3623;

            default_type 'application/json';

            location /embeddings {
                content_by_lua_block {
                    ngx.say([[$embeddings]])
                }
            }

            location /search {
                content_by_lua_block {
                    ngx.print("azure passed")
                }
            }

            location ~ ^/collections/([^/]+)/points/query\$ {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local collection = ngx.var[1]
                    local api_key = ngx.req.get_headers()["api-key"]

                    if collection == "open" then
                        ngx.say(json.encode({ result = { points = {
                            { id = 1, payload = { auth = api_key or "none" } } } } }))
                        return
                    end
                    if api_key ~= "key" then
                        ngx.status = 401
                        ngx.say("Must provide an API key")
                        return
                    end
                    if collection == "missing" then
                        ngx.status = 404
                        ngx.say([[{"status":{"error":"Not found: Collection missing"}}]])
                        return
                    end
                    if collection == "badfilter" then
                        ngx.status = 400
                        ngx.say([[{"status":{"error":"Bad filter"}}]])
                        return
                    end
                    if collection == "broken" then
                        ngx.say([[{"result":"unexpected"}]])
                        return
                    end
                    if collection == "empty" then
                        ngx.say([[{"result":{"points":[{"id":1},{"id":2,"payload":{}}]}}]])
                        return
                    end

                    ngx.req.read_body()
                    local body = json.decode(ngx.req.get_body_data())
                    if body.query[1] ~= 123456789 then
                        ngx.status = 400
                        ngx.say([[{"status":{"error":"bad query vector"}}]])
                        return
                    end
                    ngx.say(json.encode({ result = { points = {
                        { id = 1, score = 0.9, payload = { text = "doc one" } },
                        { id = 2, score = 0.8, payload = { query = ngx.req.get_body_data() } },
                        { id = 3, score = 0.5 },
                    } } }))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: configuration validation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rag")
            local qdrant = { endpoint = "http://127.0.0.1:6333", collection_name = "docs" }
            local cases = {
                { qdrant = qdrant },
                { qdrant = { endpoint = "https://q.example.com/prefix/", api_key = "k",
                             collection_name = "docs" } },
                { qdrant = { endpoint = "http://127.0.0.1:6333" } },
                { qdrant = { collection_name = "docs" } },
                { qdrant = { endpoint = "127.0.0.1:6333", collection_name = "docs" } },
                { qdrant = { endpoint = "http://127.0.0.1:6333", collection_name = "docs",
                             apikey = "typo" } },
                { qdrant = qdrant, azure_ai_search = { endpoint = "http://a", api_key = "k" } },
                {},
                { qdrnt = qdrant },
            }
            for _, providers in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    embeddings_provider = {
                        azure_openai = { api_key = "key", endpoint = "http://a.b.com" }
                    },
                    vector_search_provider = providers,
                })
                ngx.say(ok and "ok" or err)
            end
        }
    }
--- response_body eval
qr/^ok
ok
.*property "collection_name" is required
.*property "endpoint" is required
.*property "endpoint" validation failed: failed to match pattern.*
.*additional properties forbidden, found apikey
.*expect object to have at most 1 properties
.*expect object to have at least 1 properties
.*additional properties forbidden, found qdrnt
$/



=== TEST 2: qdrant api_key is encrypted in etcd
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-rag": {
                            "embeddings_provider": {
                                "azure_openai": {
                                    "endpoint": "http://localhost:3623/embeddings",
                                    "api_key": "key"
                                }
                            },
                            "vector_search_provider": {
                                "qdrant": {
                                    "endpoint": "http://localhost:3623",
                                    "api_key": "key",
                                    "collection_name": "docs"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            local api_key = res.body.node.value.plugins["ai-rag"]
                            .vector_search_provider.qdrant.api_key
            ngx.say(api_key:sub(1, 5))
        }
    }
--- response_body
$ENC$



=== TEST 3: payloads of matched points are added to the messages
--- request
POST /echo
{"messages":[{"role":"user","content":"Q"}],"ai_rag":{"vector_search":{},"embeddings":{"input":"devops"}}}
--- error_code: 200
--- response_body eval
qr/^(?=.*"content":"Q")(?=.*"content":"\[\{\\"text\\":\\"doc one\\"\},\{\\"query\\":)(?=.*\\\\\\"with_payload\\\\\\":true)(?!.*ai_rag)(?!.*score)/s



=== TEST 4: search parameters are sent to qdrant with exact numbers
--- request
POST /echo
{"ai_rag":{"vector_search":{"limit":2,"using":"content","score_threshold":0.5,"with_payload":["query"],"params":{"exact":true},"filter":{"must":[{"key":"n","match":{"value":1234567890123456}}]}},"embeddings":{"input":"devops"}}}
--- error_code: 200
--- response_body eval
qr/^(?=.*\\\\\\"limit\\\\\\":2)(?=.*\\\\\\"using\\\\\\":\\\\\\"content\\\\\\")(?=.*\\\\\\"score_threshold\\\\\\":0.5)(?=.*\\\\\\"with_payload\\\\\\":\[\\\\\\"query\\\\\\"\])(?=.*\\\\\\"exact\\\\\\":true)(?=.*\\\\\\"value\\\\\\":1234567890123456)/s



=== TEST 5: invalid vector_search fields are rejected
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local qdrant = require("apisix.plugins.ai-rag.vector-search.qdrant")
            for _, c in ipairs({
                '{}', '{"limit":100}', '{"limit":0}', '{"limit":101}', '{"limit":"3"}',
                '{"with_payload":[]}', '{"with_payload":true}', '{"filter":"x"}', '{"limt":2}',
            }) do
                local ok = core.schema.check(qdrant.request_schema, core.json.decode(c))
                ngx.say(c, " ", ok and "ok" or "rejected")
            end
        }
    }
--- response_body
{} ok
{"limit":100} ok
{"limit":0} rejected
{"limit":101} rejected
{"limit":"3"} rejected
{"with_payload":[]} rejected
{"with_payload":true} rejected
{"filter":"x"} rejected
{"limt":2} rejected



=== TEST 6: qdrant errors give generic responses, and no payload adds no message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local cases = {
                { "missing", "key" }, { "badfilter", "key" }, { "broken", "key" },
                { "docs", "wrong" }, { "empty", "key" }, { "open" },
            }
            for i, c in ipairs(cases) do
                local api_key = c[2] and ('"api_key": "' .. c[2] .. '",') or ""
                local code, body = t('/apisix/admin/routes/' .. i, ngx.HTTP_PUT, [[{
                    "uri": "/r]] .. i .. [[",
                    "plugins": {
                        "proxy-rewrite": { "uri": "/echo" },
                        "ai-rag": {
                            "embeddings_provider": { "azure_openai": {
                                "endpoint": "http://localhost:3623/embeddings",
                                "api_key": "key" } },
                            "vector_search_provider": { "qdrant": {
                                "endpoint": "http://localhost:3623", ]] .. api_key .. [[
                                "collection_name": "]] .. c[1] .. [[" } }
                        }
                    },
                    "upstream": { "type": "roundrobin", "nodes": { "127.0.0.1:1980": 1 } }
                }]])
                if code >= 300 then
                    ngx.say(body)
                    return
                end
            end
            ngx.sleep(0.5)

            for i, c in ipairs(cases) do
                local res = http.new():request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                                   .. "/r" .. i, {
                    method = "POST",
                    headers = { ["Content-Type"] = "application/json" },
                    body = [[{"messages":[{"role":"user","content":"Q"}],]]
                           .. [["ai_rag":{"vector_search":{},"embeddings":{"input":"x"}}}]],
                })
                local body = res.body
                if res.status == 200 then
                    local messages = require("cjson").decode(body).messages
                    body = #messages .. " " .. messages[#messages].content
                end
                ngx.say(c[1], " ", res.status, " ", body)
            end
        }
    }
--- response_body
missing 502 vector search failed
badfilter 400 invalid vector search query
broken 502 vector search failed
docs 502 vector search failed
empty 200 1 Q
open 200 2 [{"auth":"none"}]
--- error_log
Qdrant returned status 404: {"status":{"error":"Not found: Collection missing"}}
Qdrant returned status 400: {"status":{"error":"Bad filter"}}
invalid Qdrant response: {"result":"unexpected"}
Qdrant returned status 401: Must provide an API key
no Qdrant payloads matched the query



=== TEST 7: request URI and headers
--- config
    location /t {
        content_by_lua_block {
            local qdrant = require("apisix.plugins.ai-rag.vector-search.qdrant")
            local captured
            local httpc = {
                request_uri = function(_, uri, opts)
                    captured = { uri = uri, opts = opts }
                    return { status = 200, body = '{"result":{"points":[]}}' }
                end
            }
            qdrant.search({ endpoint = "http://q:6333//", collection_name = "my docs" },
                          { embeddings = { 0.5 } }, httpc, false)
            ngx.say(captured.uri, " ", tostring(captured.opts.headers["api-key"]), " ",
                    tostring(captured.opts.ssl_verify))
            qdrant.search({ endpoint = "https://q", collection_name = "docs", api_key = "k" },
                          { embeddings = { 0.5 } }, httpc, true)
            ngx.say(captured.uri, " ", captured.opts.headers["api-key"], " ",
                    tostring(captured.opts.ssl_verify))
        }
    }
--- response_body
http://q:6333/collections/my%20docs/points/query nil false
https://q/collections/docs/points/query k true



=== TEST 8: routes with different vector search providers validate their own request body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local providers = {
                { "/azure", [["azure_ai_search": { "endpoint": "http://localhost:3623/search",
                                                  "api_key": "key" }]],
                  [[{"fields":"v"}]] },
                { "/qdrant", [["qdrant": { "endpoint": "http://localhost:3623",
                                          "api_key": "key", "collection_name": "docs" }]],
                  [[{"limit":1}]] },
            }
            for i, p in ipairs(providers) do
                local code, body = t('/apisix/admin/routes/' .. i, ngx.HTTP_PUT, [[{
                    "uri": "]] .. p[1] .. [[",
                    "plugins": {
                        "proxy-rewrite": { "uri": "/echo" },
                        "ai-rag": {
                            "embeddings_provider": { "azure_openai": {
                                "endpoint": "http://localhost:3623/embeddings",
                                "api_key": "key" } },
                            "vector_search_provider": { ]] .. p[2] .. [[ }
                        }
                    },
                    "upstream": { "type": "roundrobin", "nodes": { "127.0.0.1:1980": 1 } }
                }]])
                if code >= 300 then
                    ngx.say(body)
                    return
                end
            end
            ngx.sleep(0.5)

            for _, p in ipairs(providers) do
                local res = http.new():request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                                   .. p[1], {
                    method = "POST",
                    headers = { ["Content-Type"] = "application/json" },
                    body = [[{"ai_rag":{"vector_search":]] .. p[3]
                           .. [[,"embeddings":{"input":"x"}}}]],
                })
                ngx.say(p[1], " ", res.status)
            end
        }
    }
--- response_body
/azure 200
/qdrant 200
--- no_error_log
request body fails schema check
