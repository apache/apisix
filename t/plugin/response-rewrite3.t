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

=== TEST 1: set route use response-rewrite body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed


=== TEST 4: response-rewrite route should rewrite body and not Content-Encoding
--- request
GET /hello
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 5: response-rewrite route should rewrite body and not Content-Encoding
--- http_config
gzip on;
gzip_types *;
gzip_min_length 1;
--- request
GET /hello
--- response_body
new body
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding:




=== TEST 4: set response-rewrite route, use response-rewrite filter conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
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
                                    "replace": "test",
                                    "scope":"global"
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


=== TEST 6: response-rewrite route should rewrite body and not Content-Encoding
--- request
GET /hello
--- response_body
test world
--- response_headers
Content-Encoding:



=== TEST 7: response-rewrite route should rewrite body and not Content-Encoding
--- http_config
gzip on;
gzip_types *;
gzip_min_length 1;
--- request
GET /hello
--- response_body
new body
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding:
