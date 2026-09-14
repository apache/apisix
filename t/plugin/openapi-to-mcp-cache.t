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

=== TEST 1: tools are built from the fetched spec
--- http_config
    server {
        listen 11454;
        location /openapi.json {
            content_by_lua_block {
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{"openapi":"3.0.0","paths":{"/pet":{"get":{"operationId":"listPets"}}}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.plugins.openapi-to-mcp.cache")
            local tools, err = cache.get_tools({
                openapi_url = "http://127.0.0.1:11454/openapi.json",
            })
            ngx.say(err == nil)
            ngx.say(#tools, ",", tools[1].name)
        }
    }
--- response_body
true
1,listPets



=== TEST 2: a second call with the same conf hits the cache
--- http_config
    server {
        listen 11455;
        location /openapi.json {
            content_by_lua_block {
                local n = (package.loaded._mcp_spec_hits or 0) + 1
                package.loaded._mcp_spec_hits = n
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{"openapi":"3.0.0","paths":{"/p' .. n .. '":{"get":{}}}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.plugins.openapi-to-mcp.cache")
            local conf = { openapi_url = "http://127.0.0.1:11455/openapi.json" }
            local first = cache.get_tools(conf)
            local second = cache.get_tools(conf)
            ngx.say(first[1].name, ",", second[1].name)
            ngx.say(package.loaded._mcp_spec_hits)
        }
    }
--- response_body
GetP1,GetP1
1



=== TEST 3: flatten_parameters is part of the cache key
--- http_config
    server {
        listen 11456;
        location /openapi.json {
            content_by_lua_block {
                local n = (package.loaded._mcp_spec_hits or 0) + 1
                package.loaded._mcp_spec_hits = n
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{"openapi":"3.0.0","paths":{"/p' .. n .. '":{"get":{' ..
                        '"parameters":[{"name":"q","in":"query","schema":{"type":"string"}}]}}}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.plugins.openapi-to-mcp.cache")
            local url = "http://127.0.0.1:11456/openapi.json"
            local nested = cache.get_tools({ openapi_url = url, flatten_parameters = false })
            local flat = cache.get_tools({ openapi_url = url, flatten_parameters = true })
            ngx.say(nested[1].input_schema.properties.queryParameters ~= nil)
            ngx.say(flat[1].input_schema.properties.q ~= nil)
            ngx.say(package.loaded._mcp_spec_hits)
        }
    }
--- response_body
true
true
2



=== TEST 4: a fetch failure surfaces the error and caches nothing durably
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.plugins.openapi-to-mcp.cache")
            local tools, err = cache.get_tools({
                openapi_url = "http://127.0.0.1:11499/missing.json",
            })
            ngx.say(tools == nil)
            ngx.say(err ~= nil)
        }
    }
--- response_body
true
true



=== TEST 5: $ref inside the spec is resolved before tools are generated
--- http_config
    server {
        listen 11457;
        location /openapi.json {
            content_by_lua_block {
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{"openapi":"3.0.0",' ..
                        '"components":{"parameters":{"Limit":{"name":"limit","in":"query",' ..
                        '"schema":{"type":"integer"}}}},' ..
                        '"paths":{"/pet":{"get":{"operationId":"listPets",' ..
                        '"parameters":[{"$ref":"#/components/parameters/Limit"}]}}}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.plugins.openapi-to-mcp.cache")
            local tools = cache.get_tools({
                openapi_url = "http://127.0.0.1:11457/openapi.json",
                flatten_parameters = true,
            })
            ngx.say(tools[1].input_schema.properties.limit.type)
            ngx.say(tools[1].execution_parameters[1].name)
        }
    }
--- response_body
integer
limit
