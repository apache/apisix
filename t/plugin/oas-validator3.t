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
    server {
        listen 1979;
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
