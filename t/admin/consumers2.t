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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.value.create_time = nil
            res.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/consumers/jack","value":{"username":"jack"}}



=== TEST 2: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/consumers/jack',
                ngx.HTTP_GET
            )

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
            assert(res.value.create_time ~= nil)
            res.value.create_time = nil
            assert(res.value.update_time ~= nil)
            res.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/consumers/jack","value":{"username":"jack"}}



=== TEST 3: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/consumers/jack',
                ngx.HTTP_DELETE
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
{"deleted":"1","key":"/apisix/consumers/jack"}



=== TEST 4: list empty resources
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/consumers',
                ngx.HTTP_GET
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
{"list":[],"total":0}



=== TEST 5: mismatched username, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/consumers/jack1',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack"
                }]]
            )

            ngx.print(message)
        }
    }
--- response_body
{"error_msg":"wrong username"}



=== TEST 6: create consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username": "jack",
                     "desc": "key-auth for jack",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
                }]]
            )
        }
    }
--- request
GET /t



=== TEST 7: duplicate consumer key, PUT
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username": "jack2",
                     "desc": "key-auth for jack2",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
                     }
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
{"error_msg":"duplicate key found with consumer: jack"}



=== TEST 8: update consumer jack
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username": "jack",
                     "desc": "key-auth for jack",
                     "plugins": {
                         "key-auth": {
                             "key": "the-key"
                         }
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
