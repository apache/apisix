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
no_shuffle();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity - check_schema accepts valid config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.stream.plugins.sr-enable-disable")
            local ok, err = plugin.check_schema({enabled = true})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: check_schema rejects missing required field
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.stream.plugins.sr-enable-disable")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body eval
qr/property "enabled" is required/



=== TEST 3: check_schema rejects additional properties
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.stream.plugins.sr-enable-disable")
            local ok, err = plugin.check_schema({enabled = true, unknown = "bad"})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body eval
qr/additional properties forbidden/



=== TEST 4: set upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: set stream route with enabled = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "sr-enable-disable": {
                            "enabled": true
                        }
                    },
                    "upstream_id": "1"
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



=== TEST 6: connection allowed when enabled
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 7: set stream route with enabled = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "sr-enable-disable": {
                            "enabled": false
                        }
                    },
                    "upstream_id": "1"
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



=== TEST 8: connection rejected when disabled
--- stream_request eval
mmm
--- error_log
sr-enable-disable: refusing stream connection



=== TEST 9: set stream route with custom decline_msg
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "sr-enable-disable": {
                            "enabled": false,
                            "decline_msg": "Maintenance mode active."
                        }
                    },
                    "upstream_id": "1"
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



=== TEST 10: custom decline_msg appears in log
--- stream_request eval
mmm
--- error_log
Maintenance mode active.



=== TEST 11: toggle from disabled back to enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "sr-enable-disable": {
                            "enabled": true
                        }
                    },
                    "upstream_id": "1"
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



=== TEST 12: connection allowed again after re-enabling
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 13: validate schema via admin API - missing enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "sr-enable-disable": {
                        }
                    },
                    "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of stream plugin/
