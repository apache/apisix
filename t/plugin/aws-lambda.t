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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $inside_lua_block = $block->inside_lua_block // "";
    chomp($inside_lua_block);
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8765;

        location /httptrigger {
            content_by_lua_block {
                ngx.req.read_body()
                local msg = "aws lambda invoked"
                ngx.header['Content-Length'] = #msg + 1
                ngx.header['Connection'] = "Keep-Alive"
                ngx.say(msg)
            }
        }

        location /generic {
            content_by_lua_block {
                $inside_lua_block
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: checking iam schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aws-lambda")
            local ok, err = plugin.check_schema({
                function_uri = "https://api.amazonaws.com",
                authorization = {
                    iam = {
                        accesskey = "key1",
                        secretkey = "key2"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 2: missing fields in iam schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aws-lambda")
            local ok, err = plugin.check_schema({
                function_uri = "https://api.amazonaws.com",
                authorization = {
                    iam = {
                        secretkey = "key2"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "authorization" validation failed: property "iam" validation failed: property "accesskey" is required



=== TEST 3: create route with aws plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/httptrigger",
                                "authorization": {
                                    "apikey" : "testkey"
                                }
                            }
                        },
                        "uri": "/aws"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "aws-lambda": {
                                    "keepalive": true,
                                    "timeout": 3000,
                                    "ssl_verify": true,
                                    "keepalive_timeout": 60000,
                                    "keepalive_pool": 5,
                                    "function_uri": "http://localhost:8765/httptrigger",
                                    "authorization": {
                                        "apikey": "testkey"
                                    }
                                }
                            },
                            "uri": "/aws"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: test plugin endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")

            local code, _, body, headers = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- headers proxied 2 times -- one by plugin, another by this test case
            core.response.set_header(headers)
            ngx.print(body)
        }
    }
--- response_body
aws lambda invoked
--- response_headers
Content-Length: 19



=== TEST 5: check authz header - apikey
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- passing an apikey
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "apikey": "test_key"
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-api-key"] or "")

--- response_body
passed
Authz-Header - test_key



=== TEST 6: check authz header - IAM v4 signing
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- passing the iam access and secret keys
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "iam": {
                                        "accesskey": "KEY1",
                                        "secretkey": "KeySecret"
                                    }
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body, headers = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["Authorization"] or "")
ngx.say("AMZ-Date - " .. headers["X-Amz-Date"] or "")
ngx.print("invoked")

--- response_body eval
qr/passed
Authz-Header - AWS4-HMAC-SHA256 [ -~]*
AMZ-Date - [\d]+T[\d]+Z
invoked/
