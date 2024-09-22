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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: enable the hmac auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/uri"
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



=== TEST 2: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"type":"object","$comment":"this is a mark for our injected plugin schema","title":"work with route or service object","properties":{"allowed_algorithms":{"type":"array","default":["hmac-sha1","hmac-sha256","hmac-sha512"],"items":{"type":"string","enum":["hmac-sha1","hmac-sha256","hmac-sha512"]},"minItems":1},"_meta":{"type":"object","properties":{"filter":{"description":"filter determines whether the plugin needs to be executed at runtime","type":"array"},"error_response":{"oneOf":[{"type":"string"},{"type":"object"}]},"disable":{"type":"boolean"},"priority":{"description":"priority of plugins by customized order","type":"integer"}}},"clock_skew":{"type":"integer","default":300,"minimum":1},"signed_headers":{"type":"array","items":{"type":"string","minLength":1,"maxLength":50}},"hide_credentials":{"type":"boolean","default":false},"validate_request_body":{"type":"boolean","default":false,"title":"A boolean value telling the plugin to enable body validation"}}}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 3: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","required":["key_id","secret_key"],"properties":{"secret_key":{"minLength":1,"maxLength":256,"type":"string"},"key_id":{"minLength":1,"maxLength":256,"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 4: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/hmac-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"title":"work with route or service object","type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 5: enable hmac auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed
