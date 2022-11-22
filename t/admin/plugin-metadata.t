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
log_level("info");

run_tests;

__DATA__

=== TEST 1: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]],
                [[{
                    "value": {
                        "skey": "val",
                        "ikey": 1
                    },
                    "key": "/apisix/plugin_metadata/example-plugin"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: update plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                 ngx.HTTP_PUT,
                 [[{
                    "skey": "val2",
                    "ikey": 2
                 }]],
                [[{
                    "value": {
                        "skey": "val2",
                        "ikey": 2
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)

            -- hit again
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                 ngx.HTTP_PUT,
                 [[{
                    "skey": "val2",
                    "ikey": 2
                 }]],
                [[{
                    "value": {
                        "skey": "val2",
                        "ikey": 2
                    }
                }]]
            )

            ngx.say(code)
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
200
passed



=== TEST 3: get plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "value": {
                        "skey": "val2",
                        "ikey": 2
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: delete plugin metadata
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin', ngx.HTTP_DELETE)

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: delete plugin metadata(key: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/plugin_metadata/not_found', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404



=== TEST 6: missing plugin name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata',
                ngx.HTTP_PUT,
                [[{"k": "v"}]],
                [[{
                    "value": "sdf"
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing plugin name"}



=== TEST 7: invalid plugin name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/test',
                ngx.HTTP_PUT,
                [[{"k": "v"}]],
                [[{
                    "value": "sdf"
                }]]
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid plugin name"}



=== TEST 8: verify metadata schema fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val"
                }]],
                [[{
                    "value": {
                        "skey": "val",
                        "ikey": 1
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid configuration: property \\"ikey\\" is required"\}/



=== TEST 9: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/plugin_metadata/example-plugin","value":{"ikey":1,"skey":"val"}}
--- request
GET /t



=== TEST 10: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/plugin_metadata/example-plugin', ngx.HTTP_GET)

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)

            assert(res.createdIndex ~= nil)
            res.createdIndex = nil
            assert(res.modifiedIndex ~= nil)
            res.modifiedIndex = nil

            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/plugin_metadata/example-plugin","value":{"ikey":1,"skey":"val"}}
--- request
GET /t



=== TEST 11: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/plugin_metadata/example-plugin', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"deleted":"1","key":"/apisix/plugin_metadata/example-plugin"}
--- request
GET /t
