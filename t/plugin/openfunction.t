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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openfunction")
            local ok, err = plugin.check_schema({function_uri = "http://127.0.0.1:30585/default/test-body"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: missing `function_uri`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openfunction")
            local ok, err = plugin.check_schema({timeout = 60000})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "function_uri" is required



=== TEST 3: wrong type for `function_uri`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openfunction")
            local ok, err = plugin.check_schema({function_uri = 30858})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "function_uri" validation failed: wrong type: expected string, got number



=== TEST 4: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30584/function-sample"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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



=== TEST 5: hit route (with GET request)
--- request
GET /hello
--- response_body
Hello, function-sample!



=== TEST 6: reset route with test-body function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30585/default/test-body"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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



=== TEST 7: hit route with POST method
--- request
POST /hello
test
--- response_body
Hello, test!



=== TEST 8: reset route with test-header function with service_token
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30583/",
                                "authorization": {
                                    "service_token": "test:test"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {},
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



=== TEST 9: hit route with POST request with service_token
--- request
POST /hello
--- response_body chomp
[Basic dGVzdDp0ZXN0]



=== TEST 10: reset route with test-header function without service_token
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30583/"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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



=== TEST 11: hit route with user-specific Authorization header
--- request
POST /hello
--- more_headers
authorization: user-token-xxx
--- response_body chomp
[user-token-xxx]



=== TEST 12: reset route to non-existent function_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30584/default/non-existent"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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



=== TEST 13: hit route (with non-existent function_uri)
--- request
POST /hello
test
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 404
--- response_body_like eval
qr/not found/



=== TEST 14: reset route with test-uri function and path forwarding
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openfunction": {
                                "function_uri": "http://127.0.0.1:30584"
                            }
                        },
                        "upstream": {
                            "nodes": {},
                            "type": "roundrobin"
                        },
                        "uri": "/hello/*"
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



=== TEST 15: hit route with GET method
--- request
GET /hello/openfunction
--- response_body
Hello, openfunction!
