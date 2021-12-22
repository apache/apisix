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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/u1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
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



=== TEST 2: setup consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "test",
                    "plugins": {
                        "key-auth": {
                            "disable": false,
                            "key": "test-key"
                        }
                    }
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



=== TEST 3: setup service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/s1',
                ngx.HTTP_PUT,
                [[{
                    "name": "s1",
                    "plugins": {
                        "key-auth": {
                            "disable": false
                        }
                    }
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



=== TEST 4: setup route with APISIX data
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
                            "policy": "example2",
                            "with_route": true,
                            "with_upstream": true,
                            "with_consumer": true,
                            "with_service": true
                        }
                    },
                    "upstream_id": "u1",
                    "service_id": "s1",
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



=== TEST 5: hit route (test without apikey)
--- request
GET /hello
--- more_headers
test-header: only-for-test
--- error_code: 401
--- response_body eval
qr/Missing API key found in request/



=== TEST 6: hit route (test route data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"route\":/ and qr/\"id\":\"r1\"/ and qr/\"plugins\":\{\"opa\"/ and
qr/\"with_route\":true/



=== TEST 7: hit route (test upstream data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"upstream\":/ and qr/\"id\":\"u1\"/ and qr/\"nodes\":\[\{/ and
qr/\"host\":\"127.0.0.1\"/ and qr/\"port\":1980/ and
qr/\"weight\":1/ and qr/\"with_upstream\":true/ and
qr/\"type\":\"roundrobin\"/



=== TEST 8: hit route (test consumer data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"consumer\":/ and qr/\"username\":\"test\"/ and qr/\"key\":\"test-key\"/



=== TEST 9: hit route (test service data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"service\":/ and qr/\"id\":\"s1\"/ and qr/\"query\":\"apikey\"/ and
qr/\"header\":\"apikey\"/
