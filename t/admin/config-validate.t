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
log_level("warn");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: validate configs - success with valid route
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/test",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
    }
}
--- error_code: 200



=== TEST 2: validate configs - success with multiple resource types
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/test",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ],
                "services": [
                    {
                        "id": "svc-1",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ],
                "upstreams": [
                    {
                        "id": "ups-1",
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    }
                ]
            }]]
            )

        ngx.status = code
    }
}
--- error_code: 200



=== TEST 3: validate configs - empty body
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            ""
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "invalid request body: empty request body",
            "expected empty body error, got: " .. data.error_msg)
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 4: validate configs - invalid JSON body
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            "not json"
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg and data.error_msg:find("invalid request body", 1, true),
            "expected 'invalid request body' error, got: " .. tostring(data.error_msg))
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 5: validate configs - invalid route (uri must be string)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": 123
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed msg, got: " .. tostring(data.error_msg))
        assert(data.errors and #data.errors == 1,
            "expected 1 error, got: " .. tostring(data.errors and #data.errors))
        local err = data.errors[1]
        assert(err.resource_type == "routes", "expected resource_type=routes, got: " .. tostring(err.resource_type))
        assert(err.index == 0, "expected index=0, got: " .. tostring(err.index))
        assert(err.error and err.error:find("invalid routes at index 0", 1, true),
            "expected 'invalid routes at index 0' in error, got: " .. tostring(err.error))
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 6: validate configs - duplicate route IDs
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/test1",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    },
                    {
                        "id": "r1",
                        "uri": "/test2",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        -- find the duplicate error
        local found = false
        for _, err in ipairs(data.errors) do
            if err.error and err.error:find("found duplicate id r1 in routes", 1, true) then
                found = true
                assert(err.resource_type == "routes", "expected resource_type=routes")
                assert(err.index == 1, "expected index=1 for the duplicate, got: " .. tostring(err.index))
                break
            end
        end
        assert(found, "expected 'found duplicate id r1 in routes' error in: " .. body)
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 7: validate configs - plugin check_schema advanced validation (cors)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/test",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "cors": {
                                "allow_credential": true,
                                "allow_origins": "*"
                            }
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        assert(data.errors and #data.errors >= 1, "expected at least 1 error")
        local err = data.errors[1]
        assert(err.resource_type == "routes", "expected resource_type=routes")
        -- cors check_schema rejects allow_credential=true with allow_origins="*"
        assert(err.error and err.error:find("allow_origins", 1, true),
            "expected cors allow_origins error, got: " .. tostring(err.error))
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 8: validate configs - collects all errors
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": 123
                    },
                    {
                        "id": "r2",
                        "uri": 456
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.errors and #data.errors == 2,
            "expected 2 errors, got: " .. tostring(data.errors and #data.errors))
        -- verify each error has correct index
        local indices = {}
        for _, err in ipairs(data.errors) do
            indices[err.index] = true
            assert(err.resource_type == "routes", "expected resource_type=routes")
            assert(err.error and err.error:find("invalid routes at index", 1, true),
                "expected 'invalid routes at index' in error, got: " .. tostring(err.error))
        end
        assert(indices[0] and indices[1], "expected errors at index 0 and 1")
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 9: validate configs - success with empty config (no resources)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{}]]
            )

        ngx.status = code
    }
}
--- error_code: 200



=== TEST 10: validate configs - does not persist changes
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        -- first validate a config
        local code = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "validate-test-r1",
                        "uri": "/validate-test",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ]
            }]]
            )
        assert(code == 200, "validate should succeed")

        -- then try to get the route - it should not exist
        local code, body = t('/apisix/admin/routes/validate-test-r1', ngx.HTTP_GET)
        ngx.status = code
    }
}
--- error_code: 404



=== TEST 11: validate configs - invalid plugin configuration (limit-count negative count)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/test",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        },
                        "plugins": {
                            "limit-count": {
                                "count": -1,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        assert(data.errors and #data.errors >= 1, "expected at least 1 error")
        local err = data.errors[1]
        assert(err.resource_type == "routes", "expected resource_type=routes")
        assert(err.error and err.error:find("limit%-count", 1, false),
            "expected limit-count in error, got: " .. tostring(err.error))
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 12: validate configs - invalid upstream configuration (bad type)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "upstreams": [
                    {
                        "id": "ups-1",
                        "type": "invalid_type",
                        "nodes": {"127.0.0.1:1980": 1}
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        assert(data.errors and #data.errors >= 1, "expected at least 1 error")
        local err = data.errors[1]
        assert(err.resource_type == "upstreams", "expected resource_type=upstreams, got: " .. tostring(err.resource_type))
        assert(err.index == 0, "expected index=0, got: " .. tostring(err.index))
        assert(err.error and err.error:find("invalid upstreams at index 0", 1, true),
            "expected 'invalid upstreams at index 0' in error, got: " .. tostring(err.error))
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 13: validate configs - consumer with valid plugin
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "consumers": [
                    {
                        "username": "jack",
                        "plugins": {
                            "key-auth": {
                                "key": "auth-one"
                            }
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
    }
}
--- error_code: 200



=== TEST 14: validate configs - routes without id (no crash on nil identifier)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, _, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "uri": "/foo",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    },
                    {
                        "uri": "/bar",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ],
                "services": [
                    {
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ]
            }]]
            )

        assert(code == 200, "expected 200, got: " .. tostring(code))
        ngx.say("passed")
    }
}
--- response_body
passed



=== TEST 15: validate configs - duplicate consumer usernames detected
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "consumers": [
                    {
                        "username": "jack",
                        "plugins": {
                            "key-auth": {"key": "auth-one"}
                        }
                    },
                    {
                        "username": "jack",
                        "plugins": {
                            "key-auth": {"key": "auth-two"}
                        }
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        local found = false
        for _, err in ipairs(data.errors) do
            if err.error and err.error:find("found duplicate username jack in consumers", 1, true) then
                found = true
                assert(err.resource_type == "consumers", "expected resource_type=consumers")
                break
            end
        end
        assert(found, "expected 'found duplicate username jack in consumers' error in: " .. body)
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed



=== TEST 16: validate configs - mixed valid and invalid resources across types
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local json = require("cjson")
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            [[{
                "routes": [
                    {
                        "id": "r1",
                        "uri": "/ok",
                        "upstream": {
                            "nodes": {"127.0.0.1:1980": 1},
                            "type": "roundrobin"
                        }
                    }
                ],
                "upstreams": [
                    {
                        "id": "ups-bad",
                        "type": "invalid_type",
                        "nodes": {"127.0.0.1:1980": 1}
                    }
                ],
                "consumers": [
                    {
                        "plugins": {}
                    }
                ]
            }]]
            )

        ngx.status = code
        local data = json.decode(body)
        assert(data.error_msg == "Configuration validation failed",
            "expected validation failed, got: " .. tostring(data.error_msg))
        -- should have errors from upstreams and consumers, but not routes
        local has_upstream_err = false
        local has_consumer_err = false
        local has_route_err = false
        for _, err in ipairs(data.errors) do
            if err.resource_type == "upstreams" then
                has_upstream_err = true
            elseif err.resource_type == "consumers" then
                has_consumer_err = true
            elseif err.resource_type == "routes" then
                has_route_err = true
            end
        end
        assert(has_upstream_err, "expected upstream validation error")
        assert(has_consumer_err, "expected consumer validation error (missing username)")
        assert(not has_route_err, "route should be valid, no route errors expected")
        ngx.say("passed")
    }
}
--- error_code: 400
--- response_body
passed
