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

    my $extra_yaml_config = <<_EOC_;
plugins:
    - public-api
    - batch-requests
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: pre-create public API route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/apisix/batch-requests"
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



=== TEST 2: customize uri, not found
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



=== TEST 3: create public API route for custom uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "public-api": {}
                        },
                        "uri": "/foo/bar"
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



=== TEST 4: customize uri, found
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



=== TEST 5: customize uri, missing plugin, use default
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



=== TEST 6: customize uri, missing attr, use default
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



=== TEST 7: ensure real ip header is overridden
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "headers": {
                        "x-real-ip": "127.0.0.2"
                    },
                    "pipeline":[
                    {
                        "path": "/c",
                        "method": "PUT"
                    }]
                }]=],
                [=[[
                {
                    "status": 201,
                    "body":"C",
                    "headers": {
                        "Client-IP": "127.0.0.1",
                        "Client-IP-From-Hdr": "127.0.0.1"
                    }
                }
                ]]=])

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["Client-IP"] = ngx.var.remote_addr
            ngx.header["Client-IP-From-Hdr"] = ngx.req.get_headers()["x-real-ip"]
            ngx.print("C")
        }
    }
--- request
GET /aggregate
--- response_body
passed



=== TEST 8: ensure real ip header is overridden, header from the pipeline
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "headers": {
                    },
                    "pipeline":[
                    {
                        "path": "/c",
                        "headers": {
                            "x-real-ip": "127.0.0.2"
                        },
                        "method": "PUT"
                    }]
                }]=],
                [=[[
                {
                    "status": 201,
                    "body":"C",
                    "headers": {
                        "Client-IP": "127.0.0.1",
                        "Client-IP-From-Hdr": "127.0.0.1"
                    }
                }
                ]]=])

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["Client-IP"] = ngx.var.remote_addr
            ngx.header["Client-IP-From-Hdr"] = ngx.req.get_headers()["x-real-ip"]
            ngx.print("C")
        }
    }
--- request
GET /aggregate
--- response_body
passed



=== TEST 9: ensure real ip header is overridden, header has underscore
--- config
    location = /aggregate {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "headers": {
                    },
                    "pipeline":[
                    {
                        "path": "/c",
                        "headers": {
                            "x_real-ip": "127.0.0.2"
                        },
                        "method": "PUT"
                    }]
                }]=],
                [=[[
                {
                    "status": 201,
                    "body":"C",
                    "headers": {
                        "Client-IP": "127.0.0.1",
                        "Client-IP-From-Hdr": "127.0.0.1"
                    }
                }
                ]]=])

            ngx.status = code
            ngx.say(body)
        }
    }

    location = /c {
        content_by_lua_block {
            ngx.status = 201
            ngx.header["Client-IP"] = ngx.var.remote_addr
            ngx.header["Client-IP-From-Hdr"] = ngx.req.get_headers()["x-real-ip"]
            ngx.print("C")
        }
    }
--- request
GET /aggregate
--- response_body
passed



=== TEST 10: ensure the content-type is correct
--- request
POST /apisix/batch-requests
{
    "headers": {
    },
    "pipeline":[
        {
            "path": "/c",
            "method": "PUT"
        }
    ]
}
--- response_headers
Content-Type: application/json


=== TEST 11: Ensure sub_responses count matches sub_requests on timed out sub_request (contains no empty json object like '{}' in batch response)
--- config
    location = /aggregate {
        content_by_lua_block {
            local cjson = require("cjson.safe")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body, res_body, res_header = t('/apisix/batch-requests',
                 ngx.HTTP_POST,
                 [=[{
                    "headers": {
                    },
                    "timeout": 200,
                    "pipeline":[
                    {
                        "path": "/ok",
                        "method": "GET"
                    },{
                      "path": "/timeout",
                      "method": "GET"
                    }]
                }]=])
            ngx.status = code
            -- print the number of sub-responses.
            -- the number is expected to be the same as that of the sub-requests.
            ngx.say(#cjson.decode(res_body))
        }
    }

    location = /ok {
        content_by_lua_block {
            ngx.print("ok")
        }
    }
    location = /timeout {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.print("timeout")
        }
    }
--- request
GET /aggregate
--- error_log
timeout
--- response_body
2
