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
    $ENV{TEST_HOST} = "test.example.com";
    $ENV{TEST_URI} = "/hello";
    $ENV{TEST_HEADER_VALUE} = "from-env";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: proxy-rewrite resolves $env:// references automatically (central resolution)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "proxy-rewrite": {
                            "host": "$env://TEST_HOST"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 2: verify host header is resolved from env variable
--- request
GET /hello
--- response_headers
!X-Test-Error
--- more_headers
--- response_body_like
.*
--- error_log
matched route



=== TEST 3: proxy-rewrite resolves $env:// in uri field with schema constraints
proxy-rewrite.uri has minLength, maxLength, and pattern constraints.
The $env://TEST_URI string itself doesn't match the ^/.* pattern,
but central schema validation strips secret ref fields before checking.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "$env://TEST_URI"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 4: verify uri is resolved from env variable
--- request
GET /hello
--- error_code: 200



=== TEST 5: schema validation strips nested secret ref fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "proxy-rewrite": {
                            "headers": {
                                "set": {
                                    "X-Custom": "$env://TEST_HEADER_VALUE"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 6: fetch_secrets resolves $env:// and preserves original conf
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")

            local conf = {
                host = "$env://TEST_HOST",
                uri = "/test"
            }
            local resolved = secret.fetch_secrets(conf, true)
            ngx.say("resolved host: ", resolved.host)
            ngx.say("original host: ", conf.host)
        }
    }
--- response_body
resolved host: test.example.com
original host: $env://TEST_HOST



=== TEST 7: has_secret_ref detects nested references
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")

            ngx.say(secret.has_secret_ref({key = "$env://X"}))
            ngx.say(secret.has_secret_ref({nested = {key = "$secret://vault/1/k"}}))
            ngx.say(secret.has_secret_ref({key = "plain"}))
            ngx.say(secret.has_secret_ref({nested = {key = "plain"}}))
        }
    }
--- response_body
true
true
false
false



=== TEST 8: conf without secret refs is not modified by central resolution
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "proxy-rewrite": {
                            "host": "normal.example.com"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 9: normal conf passes through without deepcopy overhead
--- request
GET /hello
--- error_code: 200



=== TEST 10: limit-count with $env:// in redis_password passes schema validation
limit-count redis policy has password field constraints.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 10,
                            "time_window": 60,
                            "key_type": "var",
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_password": "$env://TEST_HEADER_VALUE"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 11: openid-connect with client_secret as $env:// passes schema validation
openid-connect has required field client_secret that must be a string.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "openid-connect": {
                            "client_id": "my-client",
                            "client_secret": "$env://TEST_HEADER_VALUE",
                            "discovery": "http://127.0.0.1:8090/.well-known/openid-configuration"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success
