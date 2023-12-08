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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set gzip route and response-rewrite route, use response-rewrite body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "gzip": {
                            "types": "*",
                            "min_length": 1
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
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello",
                            "headers": {
                                "set": {
                                    "Accept-Encoding": "gzip"
                                }
                            }
                        },
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/rewrited_hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: gzip route should return compressed body
--- request
GET /hello
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding: gzip



=== TEST 3: response-rewrite route should rewrite body and not Content-Encoding
--- request
GET /rewrited_hello
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 4: set response-rewrite route, use response-rewrite filter conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello",
                            "headers": {
                                "set": {
                                    "Accept-Encoding": "gzip"
                                }
                            }
                        },
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/rewrited_hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: response-rewrite route should rewrite body and not Content-Encoding
--- request
GET /rewrited_hello
--- response_body
test world
--- response_headers
Content-Encoding:



=== TEST 6: set response-rewrite route use filter conf and route for mock unsupport compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "set": {
                                    "Content-Encoding": "br"
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
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello"
                        },
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/rewrited_hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 7: response-rewrite route should try rewrite body and not Content-Encoding, report error
--- request
GET /rewrited_hello
--- response_headers
Content-Encoding:
--- error_log
filters may not work as expected due to unsupported compression encoding type



=== TEST 8: set response-rewrite route use body conf and use the route for mock unsupport compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello"
                        },
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/rewrited_hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: response-rewrite route should rewrite body and not Content-Encoding
--- request
GET /rewrited_hello
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 10: set response-rewrite route not use filter conf or body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello"
                        },
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "headers": {
                                "set": {
                                    "X-Server-id": 3,
                                    "X-Server-status": "on",
                                    "Content-Type": ""
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
                    "uri": "/rewrited_hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 11: body should keep Content-Encoding
--- request
GET /rewrited_hello
--- response_headers
Content-Encoding: br
X-Server-id: 3
X-Server-status: on
Content-Type:
