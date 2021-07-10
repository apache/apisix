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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: customize uri, not found
--- yaml_config
plugin_attr:
    batch-requests:
        uri: "/foo/bar"
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/a"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /a {
        content_by_lua_block {
            ngx.status = 200
        }
    }
--- error_code: 404
--- no_error_log
[error]



=== TEST 2: customize uri, found
--- yaml_config
plugin_attr:
    batch-requests:
        uri: "/foo/bar"
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/foo/bar',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/b",
                        "headers": {
                            "Header1": "hello",
                            "Header2": "world"
                        }
                    },{
                        "path": "/c",
                        "method": "PUT"
                    },{
                        "path": "/d"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                },
                {
                    "status": 201
                },
                {
                    "status": 202
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /b {
        content_by_lua_block {
            ngx.status = 200
        }
    }
    location = /c {
        content_by_lua_block {
            ngx.status = 201
        }
    }
    location = /d {
        content_by_lua_block {
            ngx.status = 202
        }
    }



=== TEST 3: customize uri, missing plugin, use default
--- yaml_config
plugin_attr:
    x:
      uri: "/foo/bar"
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/a"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /a {
        content_by_lua_block {
            ngx.status = 200
        }
    }



=== TEST 4: customize uri, missing attr, use default
--- yaml_config
plugin_attr:
    batch-requests:
        xyz: "/foo/bar"
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                ngx.HTTP_POST,
                [=[{
                    "timeout": 100,
                    "pipeline":[
                    {
                        "path": "/a"
                    }]
                }]=],
                [=[[
                {
                    "status": 200
                }
                ]]=]
                )

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /a {
        content_by_lua_block {
            ngx.status = 200
        }
    }
