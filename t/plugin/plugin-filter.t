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

=== TEST 1: invalid _meta filter vars schema with wrong type
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



=== TEST 2: invalid _meta filter schema with wrong expr
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



=== TEST 3: proxy-rewrite plugin run with _meta filter vars
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



=== TEST 4: hit route: run proxy-rewrite plugin
--- request
GET /hello?version=v2
--- response_headers
x-api-version: v2



=== TEST 5: hit route: not run proxy-rewrite plugin
--- request
GET /hello?version=v1
--- response_body
hello world



=== TEST 6: different route，same plugin, different filter (for expr_lrucache)
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



=== TEST 7: hit route: run proxy-rewrite plugin
--- request
GET /hello1?version=v3
--- response_headers
x-api-version: v3
