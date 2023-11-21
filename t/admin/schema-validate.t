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
log_level("warn");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: validate ok
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uri": "/httpbin/*",
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 200



=== TEST 2: validate failed, wrong uri type
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uri": 666,
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg": {"property \"uri\" validation failed: wrong type: expected string, got number"}}



=== TEST 3: validate failed, length limit
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uri": "",
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"uri\" validation failed: string too short, expected at least 1, got 0"}



=== TEST 4: validate failed, array type expected
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uris": "foobar",
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"uris\" validation failed: wrong type: expected array, got string"}



=== TEST 5: validate failed, array size limit
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uris": [],
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"uris\" validation failed: expect array to have at least 1 items"}



=== TEST 6: validate failed, array unique items
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "uris": ["/foo", "/foo"],
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"uris\" validation failed: expected unique items but items 1 and 2 are equal"}



=== TEST 7: validate failed, uri or uris is mandatory
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"allOf 1 failed: value should match only one schema, but matches none"}



=== TEST 8: validate failed, enum check
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "status": 3,
                "uri": "/foo",
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"status\" validation failed: matches none of the enum values"}



=== TEST 9: validate failed, wrong combination
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "script": "xxxxxxxxxxxxxxxxxxxxx",
                "plugin_config_id": "foo"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"allOf 1 failed: value should match only one schema, but matches none"}



=== TEST 10: validate failed, id_schema check
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/routes',
            ngx.HTTP_POST,
            [[{
                "plugin_config_id": "@@@@@@@@@@@@@@@@",
                "uri": "/foo",
                "upstream": {
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "nghttp2.org": 1
                    }
                }
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"property \"plugin_config_id\" validation failed: object matches none of the required"}



=== TEST 11: upstream ok
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/upstreams',
            ngx.HTTP_POST,
            [[{
               "nodes":{
                  "nghttp2.org":100
               },
               "type":"roundrobin"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 200



=== TEST 12: upstream failed, wrong nodes format
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/validate/upstreams',
            ngx.HTTP_POST,
            [[{
               "nodes":[
                   "nghttp2.org"
               ],
               "type":"roundrobin"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end
    }
}
--- error_code: 400
--- response
{"error_msg":"allOf 1 failed: value should match only one schema, but matches none"}



=== TEST 13: Check node_schema optional port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes',
                ngx.HTTP_POST,
                {
                    uri = "/hello",
                    upstream = {
                        type = "roundrobin",
                        nodes = {
                            { host = "127.0.0.1:1980", weight = 1,}
                        }
                    },
                    methods = {"GET"},
                }
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



=== TEST 14: Test route upstream
--- request
GET /hello
--- response_body
hello world
