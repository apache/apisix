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

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("no_error_log", "[error]");

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

no_long_string();
no_root_location();
log_level("info");
run_tests;

__DATA__

=== TEST 1: ensure all plugins have exposed their name
--- config
    location /t {
        content_by_lua_block {
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/../../apisix/plugins/") do
                if string.match(file_name, ".lua$") then
                    local expected = file_name:sub(1, #file_name - 4)
                    local plugin = require("apisix.plugins." .. expected)
                    if plugin.name ~= expected then
                        ngx.say("expected ", expected, " got ", plugin.name)
                        return
                    end
                end
            end
            ngx.say('ok')
        }
    }
--- response_body
ok



=== TEST 2: define route for /*
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
                        }
                    }
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
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



=== TEST 3: sign and verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world



=== TEST 4: delete /* and define route for /apisix/plugin/blah
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', "DELETE")
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/apisix/plugin/blah"
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



=== TEST 5: hit
--- request
GET /apisix/plugin/blah
--- error_code: 401
--- response_body
{"message":"Missing JWT token in request"}



=== TEST 6: ensure all plugins have unique priority
--- config
    location /t {
        content_by_lua_block {
            local lfs = require("lfs")
            local pri_name = {}
            for file_name in lfs.dir(ngx.config.prefix() .. "/../../apisix/plugins/") do
                if string.match(file_name, ".lua$") then
                    local name = file_name:sub(1, #file_name - 4)
                    local plugin = require("apisix.plugins." .. name)
                    if pri_name[plugin.priority] then
                        ngx.say(name, " has same priority with ", pri_name[plugin.priority])
                        return
                    end
                    pri_name[plugin.priority] = plugin.name
                end
            end
            ngx.say('ok')
        }
    }
--- response_body
ok



=== TEST 7: plugin with custom error message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {
                            "_meta": {
                                "error_response": {
                                    "message":"Missing credential in request"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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



=== TEST 8: verify, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing credential in request"}



=== TEST 9: validate custom error message configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            for _, case in ipairs({
                {input = true},
                {input = {
                    error_response = true
                }},
                {input = {
                    error_response = "OK"
                }},
            }) do
                local code, body = t('/apisix/admin/plugin_configs/1',
                    ngx.HTTP_PUT,
                    {
                        plugins = {
                            ["jwt-auth"] = {
                                _meta = case.input
                            }
                        }
                    }
                )
                if code >= 300 then
                    ngx.print(body)
                else
                    ngx.say(body)
                end
            end
        }
    }
--- response_body
{"error_msg":"failed to check the configuration of plugin jwt-auth err: property \"_meta\" validation failed: wrong type: expected object, got boolean"}
{"error_msg":"failed to check the configuration of plugin jwt-auth err: property \"_meta\" validation failed: property \"error_response\" validation failed: value should match only one schema, but matches none"}
passed



=== TEST 10: invalid _meta filter vars schema with wrong type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["jwt-auth"] = {
                            _meta = {
                                filter = "arg_k == v"
                            }
                        }
                    }
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
{"error_msg":"failed to check the configuration of plugin jwt-auth err: property \"_meta\" validation failed: property \"filter\" validation failed: wrong type: expected array, got string"}



=== TEST 11: invalid _meta filter schema with wrong expr
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            for _, filter in ipairs({
                {"arg_name", "==", "json"},
                {
                    {"arg_name", "*=", "json"}
                }
            }) do
                local code, body = t('/apisix/admin/plugin_configs/1',
                    ngx.HTTP_PUT,
                    {
                        plugins = {
                            ["jwt-auth"] = {
                                _meta = {
                                    filter = filter
                                }
                            }
                        }
                    }
                )
                if code >= 300 then
                    ngx.print(body)
                else
                    ngx.say(body)
                end
            end
        }
    }
--- response_body
{"error_msg":"failed to validate the 'vars' expression: rule should be wrapped inside brackets"}
{"error_msg":"failed to validate the 'vars' expression: invalid operator '*='"}



=== TEST 12: proxy-rewrite plugin run with _meta filter vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["proxy-rewrite"] = {
                            _meta = {
                                filter = {
                                    {"arg_version", "==", "v2"}
                                }
                            },
                            uri = "/echo",
                            headers = {
                                ["X-Api-Version"] = "v2"
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello"
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 13: hit route: run proxy-rewrite plugin
--- request
GET /hello?version=v2
--- response_headers
x-api-version: v2



=== TEST 14: hit route: not run proxy-rewrite plugin
--- request
GET /hello?version=v1
--- response_body
hello world



=== TEST 15: different route，same plugin, different filter (for expr_lrucache)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["proxy-rewrite"] = {
                            _meta = {
                                filter = {
                                    {"arg_version", "==", "v3"}
                                }
                            },
                            uri = "/echo",
                            headers = {
                                ["X-Api-Version"] = "v3"
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello1"
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 16: hit route: run proxy-rewrite plugin
--- request
GET /hello1?version=v3
--- response_headers
x-api-version: v3



=== TEST 17: same plugin, same id between routes and global_rules, different filter (for expr_lrucache)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/2',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["proxy-rewrite"] = {
                            _meta = {
                                filter = {
                                    {"arg_version", "==", "v4"}
                                }
                            },
                            uri = "/echo",
                            headers = {
                                ["X-Api-Version"] = "v4"
                            }
                        }
                    }
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 18: hit route: run global proxy-rewrite plugin
--- request
GET /hello1?version=v4
--- response_headers
x-api-version: v4



=== TEST 19: different global_rules with the same plugin will not use the same meta.filter cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/3',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["proxy-rewrite"] = {
                            _meta = {
                                filter = {
                                    {"arg_version", "==", "v5"}
                                }
                            },
                            uri = "/echo",
                            headers = {
                                ["X-Api-Version"] = "v5"
                            }
                        }
                    }
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 20: hit global_rules which has the same plugin with different meta.filter
--- pipelined_requests eval
["GET /hello1?version=v4", "GET /hello1?version=v5"]
--- response_headers eval
["x-api-version: v4", "x-api-version: v5"]



=== TEST 21: use _meta.filter in response-rewrite plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "response-rewrite": {
                                "_meta": {
                                    "filter": [
                                        ["upstream_status", "~=", 200]
                                    ]
                                },
                                "headers": {
                                    "set": {
                                        "test-header": "error"
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 22: upstream_status = 502, enable response-rewrite plugin
--- request
GET /specific_status
--- more_headers
x-test-upstream-status: 502
--- response_headers
test-header: error
--- error_code: 502



=== TEST 23: upstream_status = 200, disable response-rewrite plugin
--- request
GET /hello
--- response_headers
!test-header



=== TEST 24: use _meta.filter in response-rewrite plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "headers": {
                                    "foo-age": "$arg_age"
                                }
                            },
                            "response-rewrite": {
                                "_meta": {
                                    "filter": [
                                        ["http_foo_age", "==", "18"]
                                    ]
                                },
                               "status_code": 403
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 25: proxy-rewrite plugin will set $http_foo_age, response-rewrite plugin return 403
--- request
GET /hello?age=18
--- error_code: 403



=== TEST 26: response-rewrite plugin disable, return 200
--- request
GET /hello



=== TEST 27: use response var in meta.filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "_meta": {
                                    "filter": [
                                        ["upstream_status", "==", "200"]
                                    ]
                                },
                                "uri": "/echo",
                                "headers": {
                                    "x-version": "v1"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 28: hit route: disable proxy-rewrite plugin
--- request
GET /hello
--- response_headers
!x-version



=== TEST 29: use APISIX's built-in variables in  meta.filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                {
                    plugins = {
                        ["proxy-rewrite"] = {
                            _meta = {
                                filter = {
                                    {"post_arg_key", "==", "abc"}
                                }
                            },
                            uri = "/echo",
                            headers = {
                                ["X-Api-Version"] = "ga"
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        }
                    },
                    uri = "/hello"
                }
            )
            if code >= 300 then
                ngx.print(body)
            else
                ngx.say(body)
            end
        }
    }
--- response_body
passed



=== TEST 30: hit route: proxy-rewrite enable with post_arg_xx in meta.filter
--- request
POST /hello
key=abc
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- response_headers
x-api-version: ga
