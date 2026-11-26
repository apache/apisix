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

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-req-global")
            local ok, err = plugin.check_schema({global_rate = 1, global_burst = 0,
                                                 rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: missing required fields
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-req-global")
            local ok, err = plugin.check_schema({global_burst = 0, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "global_rate" is required
done



=== TEST 3: metadata schema validation
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.limit-req-global")
            local ok, err = plugin.check_schema({instance_count = 3},
                                                 core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 4: metadata schema validation - missing required field
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.limit-req-global")
            local ok, err = plugin.check_schema({}, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "instance_count" is required
done



=== TEST 5: metadata schema validation - invalid instance_count
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.limit-req-global")
            local ok, err = plugin.check_schema({instance_count = 0},
                                                 core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "instance_count" validation failed: expected 0 to be greater than or equal to 1
done



=== TEST 6: set metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/limit-req-global',
                ngx.HTTP_PUT,
                [[{
                    "instance_count": 1
                }]],
                [[{
                    "value": {
                        "instance_count": 1
                    },
                    "key": "/apisix/plugin_metadata/limit-req-global"
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



=== TEST 7: add plugin route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "plugins": {
                         "limit-req-global": {
                             "global_rate": 4,
                             "global_burst": 2,
                             "rejected_code": 503,
                             "key": "remote_addr"
                         }
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
--- request
GET /t
--- response_body
passed



=== TEST 8: not exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]



=== TEST 9: update plugin with lower rate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "plugins": {
                         "limit-req-global": {
                             "global_rate": 0.1,
                             "global_burst": 0.1,
                             "rejected_code": 503,
                             "key": "remote_addr"
                         }
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
--- request
GET /t
--- response_body
passed



=== TEST 10: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]



=== TEST 11: wrong type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "plugins": {
                         "limit-req-global": {
                             "global_rate": -1,
                             "global_burst": 0.1,
                             "rejected_code": 503,
                             "key": "remote_addr"
                         }
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-req-global err: property \"global_rate\" validation failed: expected -1 to be greater than 0"}



=== TEST 12: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                         "plugins": {
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
--- request
GET /t
--- response_body
passed



=== TEST 13: delete route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 14: delete metadata
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/limit-req-global',
                ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
