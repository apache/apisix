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

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11451;
        gzip on;
        gzip_types *;
        gzip_min_length 1;
        location /gzip_hello {
            content_by_lua_block {
                ngx.req.read_body()
                local s = "hello world"
                ngx.header['Content-Length'] = #s + 1
                ngx.say(s)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: set route use gzip upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 2: should return gzip body
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding: gzip



=== TEST 3: set route use gzip upstream and response-rewrite body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
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
--- request
GET /t
--- response_body
passed



=== TEST 4: should rewrite body and clear Content-Encoding header
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 5: set route use gzip upstream and response-rewrite filter conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
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
                    }
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



=== TEST 6: gzip decode support, should rewrite body and clear Content-Encoding header
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_body
test world
--- response_headers
Content-Encoding:



=== TEST 7: set route use response-write body conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 8: use body conf will ignore encoding, should rewrite body and clear Content-Encoding header
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 9: set route use response-write filter conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
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
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: use filter conf will report unsupported encoding type error
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_headers
Content-Encoding:
--- error_log
filters may not work as expected due to unsupported compression encoding type: deflate



=== TEST 11: set route use response-write plugin but not use filter conf or body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
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
                    }
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



=== TEST 12: should keep Content-Encoding
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding: gzip
X-Server-id: 3
X-Server-status: on
Content-Type:



=== TEST 13: response-write without filter conf or body conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
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
                    }
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



=== TEST 14: should keep Content-Encoding
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_headers
Content-Encoding: deflate
X-Server-id: 3
X-Server-status: on
Content-Type:
