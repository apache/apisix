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

=== TEST 1: json spec parses and keeps path order
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local body = '{"openapi":"3.0.0","paths":{"/zebra":{"get":{}},"/apple":{"get":{}},"/mango":{"get":{}}}}'
            local spec, order, err = loader.parse(body)
            ngx.say(err == nil)
            ngx.say(spec.openapi)
            ngx.say(order["/zebra"], ",", order["/apple"], ",", order["/mango"])
        }
    }
--- response_body
true
3.0.0
1,2,3



=== TEST 2: yaml spec parses and keeps path order
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local body = table.concat({
                "openapi: 3.0.0",
                "paths:",
                "  /zebra:",
                "    get: {}",
                "  /apple:",
                "    get: {}",
            }, "\n")
            local spec, order, err = loader.parse(body)
            ngx.say(err == nil)
            ngx.say(spec.openapi)
            ngx.say(order["/zebra"], ",", order["/apple"])
        }
    }
--- response_body
true
3.0.0
1,2



=== TEST 3: invalid content returns error
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local spec, order, err = loader.parse("{ not json and: [not yaml")
            ngx.say(spec == nil)
            ngx.say(err ~= nil)
        }
    }
--- response_body
true
true



=== TEST 4: fetch pulls a spec over http
--- http_config
    server {
        listen 11452;
        location /openapi.json {
            content_by_lua_block {
                ngx.header["Content-Type"] = "application/json"
                ngx.say('{"openapi":"3.0.0","paths":{"/a":{"get":{}}}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local spec, order, err = loader.fetch("http://127.0.0.1:11452/openapi.json")
            ngx.say(err == nil)
            ngx.say(spec.openapi, ",", order["/a"])
        }
    }
--- response_body
true
3.0.0,1



=== TEST 5: fetch reports non-200 as error
--- http_config
    server {
        listen 11453;
        location / {
            content_by_lua_block { ngx.exit(404) }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local spec, order, err = loader.fetch("http://127.0.0.1:11453/nope.json")
            ngx.say(spec == nil)
            ngx.say(err)
        }
    }
--- response_body
true
unexpected status 404 while fetching openapi spec



=== TEST 6: paths with template parameters keep document order
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local body = '{"openapi":"3.0.0","paths":{"/pets/{petId}":{"get":{}},"/pets":{"get":{}}}}'
            local spec, order, err = loader.parse(body)
            ngx.say(err == nil)
            ngx.say(order["/pets/{petId}"], ",", order["/pets"])
        }
    }
--- response_body
true
1,2



=== TEST 7: descriptions mentioning a slash path do not shift the order
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            local body = '{"openapi":"3.0.0","info":{"description":"see /apple : the fruit"},' ..
                         '"paths":{"/zebra":{"get":{}},"/apple":{"get":{}}}}'
            local spec, order, err = loader.parse(body)
            ngx.say(err == nil)
            ngx.say(order["/zebra"], ",", order["/apple"])
        }
    }
--- response_body
true
1,2



=== TEST 8: a JSON document that escapes the solidus still yields document order
--- config
    location /t {
        content_by_lua_block {
            local loader = require("apisix.plugins.openapi-to-mcp.openapi.loader")
            -- cjson escapes "/" as "\/" by default; the key must still be
            -- recognised, otherwise every path falls back to sorted order
            local body = '{"openapi":"3.0.0","paths":{"\\/zebra":{"get":{}},' ..
                         '"\\/apple":{"get":{}},"\\/mango":{"get":{}}}}'
            local spec, order, err = loader.parse(body)
            ngx.say(err == nil)
            ngx.say(order["/zebra"], ",", order["/apple"], ",", order["/mango"])
        }
    }
--- response_body
true
1,2,3
