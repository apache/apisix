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

=== TEST 1: not unwanted data, POST
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services',
                 ngx.HTTP_POST,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.key = nil
            assert(res.value.create_time ~= nil)
            res.value.create_time = nil
            assert(res.value.update_time ~= nil)
            res.value.update_time = nil
            assert(res.value.id ~= nil)
            res.value.id = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"value":{"upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}



=== TEST 2: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
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
{"key":"/apisix/services/1","value":{"id":"1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}



=== TEST 3: not unwanted data, PATCH
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1',
                 ngx.HTTP_PATCH,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
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
{"key":"/apisix/services/1","value":{"id":"1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}



=== TEST 4: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1', ngx.HTTP_GET)

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
{"key":"/apisix/services/1","value":{"id":"1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}



=== TEST 5: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/services/1',
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
{"deleted":"1","key":"/apisix/services/1"}



=== TEST 6: set service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
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
--- response_body
passed



=== TEST 7: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "service_id": 1,
                    "uri": "/index.html"
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



=== TEST 8: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1', ngx.HTTP_DELETE)
            ngx.print("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 400 message: {"error_msg":"can not delete this service directly, route [1] is still using it now"}



=== TEST 9: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed



=== TEST 10: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/services/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed
