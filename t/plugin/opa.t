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
            local test_cases = {
                {host = "http://127.0.0.1:8181", policy = "example/allow"},
                {host = "http://127.0.0.1:8181"},
                {host = 3233, policy = "example/allow"},
            }
            local plugin = require("apisix.plugins.opa")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "policy" is required
property "host" validation failed: wrong type: expected string, got number



=== TEST 2: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:8181",
                                "policy": "example"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uris": ["/hello", "/test"]
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



=== TEST 3: hit route (with correct request)
--- request
GET /hello?test=1234&user=none
--- more_headers
test-header: only-for-test
--- response_body
hello world



=== TEST 4: hit route (with wrong header request)
--- request
GET /hello?test=1234&user=none
--- more_headers
test-header: not-for-test
--- error_code: 403



=== TEST 5: hit route (with wrong query request)
--- request
GET /hello?test=abcd&user=none
--- more_headers
test-header: only-for-test
--- error_code: 403



=== TEST 6: hit route (with wrong method request)
--- request
POST /hello?test=1234&user=none
--- more_headers
test-header: only-for-test
--- error_code: 403



=== TEST 7: hit route (with wrong path request)
--- request
GET /test?test=1234&user=none
--- more_headers
test-header: only-for-test
--- error_code: 403



=== TEST 8: hit route (response status code and header)
--- request
GET /test?test=abcd&user=alice
--- more_headers
test-header: only-for-test
--- error_code: 302
--- response_headers
Location: http://example.com/auth



=== TEST 9: hit route (response multiple header reason)
--- request
GET /test?test=abcd&user=bob
--- more_headers
test-header: only-for-test
--- error_code: 403
--- response_headers
test: abcd
abcd: test



=== TEST 10: hit route (response string reason)
--- request
GET /test?test=abcd&user=carla
--- more_headers
test-header: only-for-test
--- error_code: 403
--- response
Give you a string reason



=== TEST 11: hit route (response json reason)
--- request
GET /test?test=abcd&user=dylon
--- more_headers
test-header: only-for-test
--- error_code: 403
--- response
{"code":40001,"desc":"Give you a object reason"}



=== TEST 12: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:8181",
                                "policy": "example",
                                "send_headers_upstream": ["user"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uris": ["/echo"]
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



=== TEST 13: hit route
--- request
GET /echo?test=1234&user=none
--- response_headers
user: none
