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

=== TEST 1: setup all-in-one test
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/upstreams/u1",
                    data = [[{
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }]],
                },
                {
                    url = "/apisix/admin/consumers",
                    data = [[{
                        "username": "test",
                        "plugins": {
                            "key-auth": {
                                "_meta": {
                                    "disable": false
                                },
                                "key": "test-key"
                            }
                        }
                    }]],
                },
                {
                    url = "/apisix/admin/services/s1",
                    data = [[{
                        "name": "s1",
                        "plugins": {
                            "key-auth": {
                                "_meta": {
                                    "disable": false
                                }
                            }
                        }
                    }]],
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "opa": {
                                "host": "http://127.0.0.1:8181",
                                "policy": "echo",
                                "with_route": true,
                                "with_consumer": true,
                                "with_service": true
                            }
                        },
                        "upstream_id": "u1",
                        "service_id": "s1",
                        "uri": "/hello"
                    }]],
                },
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(code..body)
            end
        }
    }
--- response_body eval
"201passed\n" x 4



=== TEST 2: hit route (test route data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"route\":/ and qr/\"id\":\"r1\"/ and qr/\"plugins\":\{\"opa\"/ and
qr/\"with_route\":true/



=== TEST 3: hit route (test consumer data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"consumer\":/ and qr/\"username\":\"test\"/ and qr/\"key\":\"test-key\"/



=== TEST 4: hit route (test service data)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body eval
qr/\"service\":/ and qr/\"id\":\"s1\"/ and qr/\"query\":\"apikey\"/ and
qr/\"header\":\"apikey\"/



=== TEST 5: setup route without service
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
                            "policy": "echo",
                            "with_route": true,
                            "with_consumer": true,
                            "with_service": true
                        }
                    },
                    "upstream_id": "u1",
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



=== TEST 6: hit route (test without service and consumer)
--- request
GET /hello
--- more_headers
test-header: only-for-test
apikey: test-key
--- error_code: 403
--- response_body_unlike eval
qr/\"service\"/ and qr/\"consumer\"/



=== TEST 7: setup route
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
                    "upstream_id": "u1",
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



=== TEST 8: hit route (with JSON empty array)
--- request
GET /hello?user=elisa
--- error_code: 403
--- response_body chomp
{"info":[]}
