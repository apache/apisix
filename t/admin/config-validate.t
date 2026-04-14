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
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            ""
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/invalid request body/



=== TEST 4: validate configs - invalid JSON body
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/configs/validate',
            ngx.HTTP_POST,
            "not json"
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/invalid request body/



=== TEST 5: validate configs - invalid route configuration
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
                        "uri": 123
                    }
                ]
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/Configuration validation failed/



=== TEST 6: validate configs - duplicate route IDs
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
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/duplicate.*r1/



=== TEST 7: validate configs - plugin check_schema advanced validation (cors)
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
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/Configuration validation failed/



=== TEST 8: validate configs - collects all errors
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
        local json = require("cjson")
        local data = json.decode(body)
        ngx.say("error_count: " .. #data.errors)
    }
}
--- error_code: 400
--- response_body
error_count: 2



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



=== TEST 11: validate configs - invalid plugin configuration
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
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/Configuration validation failed/



=== TEST 12: validate configs - invalid upstream configuration
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
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
        ngx.say(body)
    }
}
--- error_code: 400
--- response_body eval
qr/Configuration validation failed/



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
        local code, body = t('/apisix/admin/configs/validate',
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

        ngx.status = code
    }
}
--- error_code: 200
