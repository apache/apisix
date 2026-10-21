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

    my $http_config = $block->http_config // <<_EOC_;
    lua_shared_dict oas_spec_fetches 1m;

    server {
        listen 1979;
        location /counted/ {
            content_by_lua_block {
                ngx.shared.oas_spec_fetches:incr(ngx.var.uri, 1, 0)
                local file = io.open("t/spec/spec.json", "r")
                local content = file:read("*a")
                file:close()
                ngx.print(content)
            }
        }
        location /spec.json {
            content_by_lua_block {
                local file = io.open("t/spec/spec.json", "r")
                local content = file:read("*a")
                file:close()
                ngx.print(content)
            }
        }
        location /invalid.json {
            content_by_lua_block {
                ngx.print("not valid json {{{")
            }
        }
        location /not-found.json {
            content_by_lua_block {
                ngx.status = 404
                ngx.print("not found")
            }
        }
        location /spec-with-auth.json {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                if headers["X-Token"] ~= "my-secret-token" then
                    ngx.status = 403
                    ngx.print("forbidden")
                    return
                end
                local file = io.open("t/spec/spec.json", "r")
                local content = file:read("*a")
                file:close()
                ngx.print(content)
            }
        }
    }

    server {
        listen 1970;
        location / {
            content_by_lua_block {
                ngx.say("ok")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema validation -- spec_url is accepted
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local ok, err = plugin.check_schema({
                spec_url = "http://127.0.0.1:1979/spec.json"
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: schema validation -- spec and spec_url are mutually exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local ok, err = plugin.check_schema({
                spec = "{}",
                spec_url = "http://127.0.0.1:1979/spec.json"
            })
            if not ok then
                ngx.say("rejected")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
rejected



=== TEST 3: schema validation -- neither spec nor spec_url fails
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local ok, err = plugin.check_schema({
                verbose_errors = true
            })
            if not ok then
                ngx.say("rejected")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
rejected



=== TEST 4: schema validation -- spec_url must be http/https
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local ok, err = plugin.check_schema({
                spec_url = "ftp://example.com/spec.json"
            })
            if not ok then
                ngx.say("rejected")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
rejected



=== TEST 5: create route with spec_url
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/spec.json"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 6: request validation works with spec_url
--- request
POST /api/v3/pet
{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 7: invalid request body fails validation with spec_url
--- request
POST /api/v3/pet
{"invalid": "body"}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body_like: failed to validate request
--- error_log
error occurred while validating request



=== TEST 8: spec_url returning non-200 triggers error
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/not-found.json"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 9: request to route with non-200 spec_url returns 500
--- request
GET /api/v3/pet/1
--- error_code: 500
--- response_body_like: failed to parse openapi spec
--- error_log
spec URL returned status 404



=== TEST 10: spec_url returning invalid JSON triggers error
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/invalid.json"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 11: request to route with invalid JSON spec_url returns 500
--- request
GET /api/v3/pet/1
--- error_code: 500
--- response_body_like: failed to parse openapi spec
--- error_log
failed to compile openapi spec fetched from URL



=== TEST 12: spec_url with custom request headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/spec-with-auth.json",
                            "spec_url_request_headers": {
                                "X-Token": "my-secret-token"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 13: request validation works with custom headers spec_url
--- request
POST /api/v3/pet
{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 14: spec_url without required auth header fails
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/spec-with-auth.json"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 15: request to route with missing auth returns 500
--- request
GET /api/v3/pet/1
--- error_code: 500
--- response_body_like: failed to parse openapi spec
--- error_log
spec URL returned status 403



=== TEST 16: metadata schema validation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local core = require("apisix.core")
            local ok, err = plugin.check_schema({spec_url_ttl = 60}, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 17: metadata schema rejects invalid ttl
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local core = require("apisix.core")
            local ok, err = plugin.check_schema({spec_url_ttl = 0}, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say("rejected")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
rejected



=== TEST 18: set plugin metadata with custom TTL
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/plugin_metadata/oas-validator',
                ngx.HTTP_PUT,
                [[{
                    "spec_url_ttl": 2
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



=== TEST 19: create route with spec_url for TTL test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec_url": "http://127.0.0.1:1979/spec.json"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 20: first request fetches and caches spec
--- request
POST /api/v3/pet
{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 21: second request uses cached spec (no refetch)
--- request
POST /api/v3/pet
{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 22: after TTL expiry, stale validator still works (async refresh)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(3)
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/api/v3/pet", {
                method = "POST",
                body = '{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}',
                headers = {
                    ["Content-Type"] = "application/json",
                }
            })
            if not res then
                ngx.say("request failed: " .. err)
                return
            end
            ngx.say("status: " .. res.status)
        }
    }
--- response_body
status: 200
--- no_error_log
[error]



=== TEST 23: clean up metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/plugin_metadata/oas-validator',
                ngx.HTTP_DELETE
            )
            ngx.say(body)
        }
    }
--- response_body
passed


=== TEST 24: changing spec_url on a route releases the previously compiled spec
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local http = require("resty.http")
            local fetches = ngx.shared.oas_spec_fetches

            local function put_route(id, spec_url)
                local code, body = t.test('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = "/api/v3/pet",
                    host = "r" .. id .. ".test",
                    plugins = {["oas-validator"] = {spec_url = spec_url}},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1970"] = 1}},
                })
                assert(code < 300, body)
                ngx.sleep(0.5)
            end

            local function hit(id)
                local res, err = http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v3/pet", {
                    method = "POST",
                    body = '{"id": 10, "name": "doggie", "photoUrls": ["string"]}',
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Host"] = "r" .. id .. ".test",
                    },
                })
                assert(res and res.status == 200, err or (res and res.status))
            end

            local function full_gc()
                collectgarbage()
                collectgarbage()
            end
            put_route(1, "http://127.0.0.1:1979/counted/a.json")
            hit(1)
            put_route(1, "http://127.0.0.1:1979/counted/b.json")
            hit(1)
            full_gc()

            -- nothing references a.json any more, so another route declaring
            -- it has to fetch it again
            put_route(2, "http://127.0.0.1:1979/counted/a.json")
            hit(2)

            ngx.say("a: ", fetches:get("/counted/a.json"))
            ngx.say("b: ", fetches:get("/counted/b.json"))

            t.test('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/2', ngx.HTTP_DELETE)
        }
    }
--- response_body
a: 2
b: 1



=== TEST 25: routes declaring the same spec_url share one compiled spec
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local http = require("resty.http")
            local fetches = ngx.shared.oas_spec_fetches

            local function put_route(id, spec_url)
                local code, body = t.test('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = "/api/v3/pet",
                    host = "r" .. id .. ".test",
                    plugins = {["oas-validator"] = {spec_url = spec_url}},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1970"] = 1}},
                })
                assert(code < 300, body)
                ngx.sleep(0.5)
            end

            local function hit(id)
                local res, err = http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v3/pet", {
                    method = "POST",
                    body = '{"id": 10, "name": "doggie", "photoUrls": ["string"]}',
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Host"] = "r" .. id .. ".test",
                    },
                })
                assert(res and res.status == 200, err or (res and res.status))
            end

            local function full_gc()
                collectgarbage()
                collectgarbage()
            end
            put_route(1, "http://127.0.0.1:1979/counted/c.json")
            put_route(2, "http://127.0.0.1:1979/counted/c.json")
            hit(1)
            hit(2)
            hit(1)
            hit(2)

            ngx.say("c: ", fetches:get("/counted/c.json"))

            t.test('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/2', ngx.HTTP_DELETE)
        }
    }
--- response_body
c: 1



=== TEST 26: changing spec_url_ttl releases the specs held by the previous cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local http = require("resty.http")
            local fetches = ngx.shared.oas_spec_fetches

            local function put_route(id, spec_url)
                local code, body = t.test('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = "/api/v3/pet",
                    host = "r" .. id .. ".test",
                    plugins = {["oas-validator"] = {spec_url = spec_url}},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1970"] = 1}},
                })
                assert(code < 300, body)
                ngx.sleep(0.5)
            end

            local function hit(id)
                local res, err = http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v3/pet", {
                    method = "POST",
                    body = '{"id": 10, "name": "doggie", "photoUrls": ["string"]}',
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Host"] = "r" .. id .. ".test",
                    },
                })
                assert(res and res.status == 200, err or (res and res.status))
            end

            local function full_gc()
                collectgarbage()
                collectgarbage()
            end
            put_route(1, "http://127.0.0.1:1979/counted/d.json")
            hit(1)

            local code, body = t.test('/apisix/admin/plugin_metadata/oas-validator',
                ngx.HTTP_PUT, {spec_url_ttl = 7200})
            assert(code < 300, body)
            ngx.sleep(0.5)
            -- the next request replaces the cache with one for the new ttl
            put_route(2, "http://127.0.0.1:1979/counted/e.json")
            hit(2)
            full_gc()

            -- the previous cache was the last holder of d.json, so it is
            -- fetched again
            hit(1)
            ngx.say("d: ", fetches:get("/counted/d.json"))

            t.test('/apisix/admin/plugin_metadata/oas-validator', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/2', ngx.HTTP_DELETE)
        }
    }
--- response_body
d: 2



=== TEST 27: an expired spec is refetched even when another route shares it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local http = require("resty.http")
            local fetches = ngx.shared.oas_spec_fetches

            local function put_route(id, spec_url)
                local code, body = t.test('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = "/api/v3/pet",
                    host = "r" .. id .. ".test",
                    plugins = {["oas-validator"] = {spec_url = spec_url}},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1970"] = 1}},
                })
                assert(code < 300, body)
                ngx.sleep(0.5)
            end

            local function hit(id)
                local res, err = http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/api/v3/pet", {
                    method = "POST",
                    body = '{"id": 10, "name": "doggie", "photoUrls": ["string"]}',
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Host"] = "r" .. id .. ".test",
                    },
                })
                assert(res and res.status == 200, err or (res and res.status))
            end

            local function full_gc()
                collectgarbage()
                collectgarbage()
            end
            local code, body = t.test('/apisix/admin/plugin_metadata/oas-validator',
                ngx.HTTP_PUT, {spec_url_ttl = 1})
            assert(code < 300, body)
            put_route(1, "http://127.0.0.1:1979/counted/f.json")
            put_route(2, "http://127.0.0.1:1979/counted/f.json")
            hit(1)
            hit(2)
            ngx.say("f: ", fetches:get("/counted/f.json"))

            ngx.sleep(1.5)
            -- serves the stale spec and queues a background refresh
            hit(1)
            hit(2)
            ngx.sleep(1.5)
            ngx.say("f: ", fetches:get("/counted/f.json"))

            t.test('/apisix/admin/plugin_metadata/oas-validator', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t.test('/apisix/admin/routes/2', ngx.HTTP_DELETE)
        }
    }
--- response_body
f: 1
f: 2
--- timeout: 10
