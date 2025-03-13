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
use strict;
use warnings FATAL => 'all';
use t::APISIX 'no_plan';

no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /apisix/admin/routes");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});
run_tests;
__DATA__

=== TEST 1: set up configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                          "key": "auth-jack"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.say(body)
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {},
                            "proxy-rewrite": {
                               "headers": {
                                   "add": {
                                      "xtest": "123"
                                    }
                               }
                            },
                            "serverless-post-function": {
                              "functions": [
                                "return function(conf, ctx) \n ngx.say(ngx.req.get_headers().xtest); \n end"
                                ]
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
            ngx.say(body)
        }
    }
--- request
GET /t
--- timeout: 15
--- response_body
passed



=== TEST 2: the proxy-rewrite runs at 'rewrite' phase and should get executed only once
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- timeout: 15
--- response_body
123
