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
log_level("info");

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

=== TEST 1: set route(rewrite method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "POST",
                                "host": "apisix.iresty.com"
                            },
                            "vars": [ ["arg_k", "==", "v"] ],
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



=== TEST 2: doesn't hit proxy-rewrite
--- request
GET /hello



=== TEST 3: doesn't hit proxy-rewrite, becase the value doesn't match
--- request
GET /hello?k=v1



=== TEST 4: hit proxy-rewrite
--- request
GET /hello?k=v
--- error_log
plugin_proxy_rewrite get method: POST



=== TEST 5: set route(update rewrite method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "GET",
                                "host": "apisix.iresty.com"
                            },
                            "vars": [["cookie_k", "==", "v"]],
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


=== TEST 6: doesn't hit proxy-rewrite
--- request
GET /hello



=== TEST 7: desn't hit vars
--- more_headers
k: v
--- request
GET /hello




=== TEST 8: hit route and hit vars
--- more_headers
Cookie: k=cookie
--- request
GET /hello
--- error_log
plugin_proxy_rewrite get method: GET




=== TEST 9: set route(rewrite method with headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "POST",
                                "host": "apisix.iresty.com",
                                "headers":{
                                    "x-api-version":"v1"
                                },
                                "vars": [["http_k", "==", "header"], ["cookie_k", "==", "cookie"], ["arg_k", "==", "uri_arg"]],
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



=== TEST 10: doesn't hit vars
--- request
GET /hello



=== TEST 11: hit route with uri_arg
--- request
GET /hello?k=uri_arg
--- error_log
plugin_proxy_rewrite get method: POST



=== TEST 12: hit route with uri_arg
--- request
GET /hello?k=uri_arg
--- error_log
plugin_proxy_rewrite get method: POST




=== TEST 13: hit routes
--- more_headers
Cookie: k=cookie
k: header
--- request
GET /hello?k=uri_arg
--- error_log
plugin_proxy_rewrite get method: POST
