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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: schema, cache requires key_headers and a bounded ttl
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.forward-auth")
            local cases = {
                {uri = "http://127.0.0.1:8199", cache = {}},
                {uri = "http://127.0.0.1:8199", cache = {key_headers = {}}},
                {uri = "http://127.0.0.1:8199", cache = {key_headers = {"Authorization"}}},
                {uri = "http://127.0.0.1:8199", cache = {key_headers = {"Authorization"}, ttl = 0}},
                {uri = "http://127.0.0.1:8199", cache = {key_headers = {"Authorization"}, ttl = 4000}},
            }
            for _, case in ipairs(cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
property "cache" validation failed: property "key_headers" is required
property "cache" validation failed: property "key_headers" validation failed: expect array to have at least 1 items
done
property "cache" validation failed: property "ttl" validation failed: expected 0 to be at least 1
property "cache" validation failed: property "ttl" validation failed: expected 4000 to be at most 3600



=== TEST 2: set up auth service, echo upstream and cached/uncached routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                {
                    url = "/apisix/admin/upstreams/u1",
                    data = [[{
                        "nodes": { "127.0.0.1:1984": 1 },
                        "type": "roundrobin"
                    }]],
                },
                -- auth service: counts every call it actually receives so tests can
                -- assert that cache hits skip it. "deny" tokens are rejected.
                {
                    url = "/apisix/admin/routes/auth",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": [
                                    "return function(conf, ctx)
                                        local core = require(\"apisix.core\")
                                        local dict = ngx.shared[\"internal-status\"]
                                        dict:incr(\"fa_count\", 1, 0)
                                        local auth = core.request.header(ctx, \"Authorization\")
                                        if auth == \"deny\" then
                                            core.response.exit(403, \"denied\")
                                        end
                                        core.response.set_header(\"X-Auth-User\", auth)
                                        if core.request.header(ctx, \"No-Store\") == \"1\" then
                                            core.response.set_header(\"Cache-Control\", \"no-store\")
                                        end
                                        core.response.exit(200)
                                    end"
                                ]
                            }
                        },
                        "uri": "/auth"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/echo",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": [
                                    "return function (conf, ctx)
                                        local core = require(\"apisix.core\")
                                        core.response.exit(200, core.request.headers(ctx))
                                    end"
                                ]
                            }
                        },
                        "uri": "/echo"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/cached",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization", "No-Store"],
                                "upstream_headers": ["X-Auth-User"],
                                "cache": { "key_headers": ["Authorization"], "ttl": 10 }
                            },
                            "proxy-rewrite": { "uri": "/echo" }
                        },
                        "upstream_id": "u1",
                        "uri": "/cached"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/cached-uri",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "cache": { "key_headers": ["Authorization"], "ttl": 10, "include_uri": true }
                            },
                            "proxy-rewrite": { "uri": "/echo" }
                        },
                        "upstream_id": "u1",
                        "uri": "/cached-uri"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/uncached",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"]
                            },
                            "proxy-rewrite": { "uri": "/echo" }
                        },
                        "upstream_id": "u1",
                        "uri": "/uncached"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/cached-post",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_method": "POST",
                                "request_headers": ["Authorization"],
                                "cache": { "key_headers": ["Authorization"], "ttl": 10 }
                            },
                            "proxy-rewrite": { "uri": "/echo" }
                        },
                        "upstream_id": "u1",
                        "uri": "/cached-post"
                    }]],
                },
            }
            for _, d in ipairs(data) do
                local code = t(d.url, ngx.HTTP_PUT, d.data)
                if code >= 300 then
                    ngx.say("failed to set ", d.url, ": ", code)
                    return
                end
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: identical requests hit the cache, auth service called once
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call()
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984/cached",
                    {headers = {["Authorization"] = "alice"}})
                return res.status
            end
            local s1 = call()
            local s2 = call()
            ngx.say("status: ", s1, " ", s2)
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
status: 200 200
auth calls: 1



=== TEST 4: different identity is never served another's cached decision
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call(auth)
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984/cached",
                    {headers = {["Authorization"] = auth}})
                return res.status
            end
            local allowed = call("bob")     -- miss, allowed
            local denied  = call("deny")    -- different key, must be evaluated -> 403
            local hit     = call("bob")     -- cache hit
            local denied2 = call("deny")    -- cached deny, still 403
            ngx.say("allowed: ", allowed)
            ngx.say("denied: ", denied)
            ngx.say("hit: ", hit)
            ngx.say("denied2: ", denied2)
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
allowed: 200
denied: 403
hit: 200
denied2: 403
auth calls: 2



=== TEST 5: caching disabled, every request calls the auth service
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call()
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984/uncached",
                    {headers = {["Authorization"] = "carol"}})
                return res.status
            end
            call()
            call()
            call()
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
auth calls: 3



=== TEST 6: upstream Cache-Control no-store is honored, decision not cached
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call()
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984/cached",
                    {headers = {["Authorization"] = "dave", ["No-Store"] = "1"}})
                return res.status
            end
            call()
            call()
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
auth calls: 2



=== TEST 7: include_uri keys on the request URI, different URIs miss
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call(path)
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984" .. path,
                    {headers = {["Authorization"] = "erin"}})
                return res.status
            end
            call("/cached-uri?a=1")
            call("/cached-uri?a=1")   -- same uri -> hit
            call("/cached-uri?a=2")   -- different uri -> miss
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
auth calls: 2



=== TEST 8: POST body is part of the cache key, different bodies miss
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local dict = ngx.shared["internal-status"]
            dict:set("fa_count", 0)
            local function call(body)
                local httpc = http.new()
                local res = httpc:request_uri("http://127.0.0.1:1984/cached-post",
                    {method = "POST", headers = {["Authorization"] = "frank"}, body = body})
                return res.status
            end
            call("payload-a")
            call("payload-a")   -- same body -> hit
            call("payload-b")   -- different body -> miss
            ngx.say("auth calls: ", dict:get("fa_count"))
        }
    }
--- response_body
auth calls: 2
