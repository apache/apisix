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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
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



=== TEST 2: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 4: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 5: /not_found
--- request
GET /hello
--- error_code: 503



=== TEST 6: global rule for internal api (should limit)
--- yaml_config
plugins:
  - limit-count
  - node-status
--- request
GET /apisix/status
--- error_code: 503



=== TEST 7: update global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "X-VERSION":"1.0"
                            }
                        },
                        "uri-blocker": {
                            "block_rules": ["select.+(from|limit)", "(?:(union(.*?)select))"]
                        }
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



=== TEST 8: set one more global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "X-TEST":"test"
                            }
                        }
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



=== TEST 9: hit global rules
--- request
GET /hello?name=;union%20select%20
--- error_code: 403
--- response_headers
X-VERSION: 1.0
X-TEST: test



=== TEST 10: hit global rules by internal api (only check uri-blocker)
--- yaml_config
plugins:
  - response-rewrite
  - uri-blocker
  - node-status
--- request
GET /apisix/status?name=;union%20select%20
--- error_code: 403
--- response_headers
X-VERSION: 1.0
X-TEST: test



=== TEST 11: delete global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/global_rules/2', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end

            local code, body = t('/not_found', ngx.HTTP_GET)
            ngx.say(code)
            local code, body = t('/not_found', ngx.HTTP_GET)
            ngx.say(code)
        }
    }
--- request
GET /t
--- response_body
passed
404
404



=== TEST 12: empty global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "changed\n"
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
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 13: hit global rules
--- request
GET /hello
--- response_body
changed



=== TEST 14: global rule works with the consumer, after deleting the global rule, ensure no stale plugins remaining
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "test",
                    "plugins": {
                        "basic-auth": {
                            "username": "test",
                            "password": "test"
                        }
                    },
                    "desc": "test description"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
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
                return
            end

            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            -- sleep for data sync
            ngx.sleep(0.5)

            -- hit the route without authorization, should be 401
            local code, body = t('/hello',
                ngx.HTTP_PUT
            )

            if code ~= 401 then
                ngx.status = 400
                return
            end

            -- hit the route with authorization
            local code, body = t('/hello',
                ngx.HTTP_PUT,
                nil,
                nil,
                {Authorization = "Basic dGVzdDp0ZXN0"}
            )

            if code ~= 200 then
                ngx.status = code
                return
            end

            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE,
                [[{
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.5)
            -- hit the route with authorization, should be 200
            local code, body = t('/hello',
                ngx.HTTP_PUT
            )

            if code ~= 200 then
                ngx.status = code
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
