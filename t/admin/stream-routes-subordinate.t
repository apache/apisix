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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: redis
    - name: dubbo
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: create superior route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "protocol": {"name": "redis"},
                    "upstream": {
                        "nodes": {"127.0.0.1:6379": 1},
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



=== TEST 2: create subordinate route with valid superior_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                [[{
                    "protocol": {
                        "name": "redis",
                        "superior_id": "1"
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:6380": 1},
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



=== TEST 3: superior_id not exist (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/stream_routes/3',
                ngx.HTTP_PUT,
                [[{
                    "protocol": {"name": "redis", "superior_id": "999"},
                    "upstream": {
                        "nodes": {"127.0.0.1:6381": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code ~= 400 then
                ngx.say("failed: expected 400, got ", code)
                return
            end
            local data = json.decode(body)
            if not data or not data.error_msg then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            if not string.find(data.error_msg, "failed to fetch stream routes[999]", 1, true) then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: protocol mismatch (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code = t('/apisix/admin/stream_routes/4',
                ngx.HTTP_PUT,
                [[{
                    "protocol": {"name": "dubbo"},
                    "upstream": {
                        "nodes": {"127.0.0.1:20880": 1},
                        "type": "roundrobin"
                    }
                }]]
            )

            local code, body = t('/apisix/admin/stream_routes/5',
                ngx.HTTP_PUT,
                [[{
                    "protocol": {"name": "redis", "superior_id": "4"},
                    "upstream": {
                        "nodes": {"127.0.0.1:6382": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code ~= 400 then
                ngx.say("failed: expected 400, got ", code)
                return
            end
            local data = json.decode(body)
            if not data or not data.error_msg then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            if not string.find(data.error_msg, "protocol mismatch", 1, true) then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: delete superior route being referenced (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_DELETE
            )
            if code ~= 400 then
                ngx.say("failed: expected 400, got ", code)
                return
            end
            local data = json.decode(body)
            if not data or not data.error_msg then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            if not string.find(data.error_msg, "can not delete this stream route", 1, true) then
                ngx.say("failed: unexpected body: ", body)
                return
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: delete subordinate route first
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/2',
                ngx.HTTP_DELETE
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



=== TEST 7: now delete superior route should succeed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_DELETE
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
