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

run_tests;

__DATA__

=== TEST 1: invalid schema (missing headers)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.attach-consumer-label")
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
--- response_body
property "headers" is required
--- no_error_log
[error]



=== TEST 2: invalid schema (headers is an empty object)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.attach-consumer-label")
            local ok, err = plugin.check_schema({
                headers = {}
            })
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
property "headers" validation failed: expect object to have at least 1 properties
--- no_error_log
[error]



=== TEST 3: invalid schema (missing $ prefix)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.attach-consumer-label")
            local ok, err = plugin.check_schema({
                headers = {
                    ["X-Consumer-Department"] = "department",
                    ["X-Consumer-Company"] = "$company"
                }
            })
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
property "headers" validation failed: failed to validate additional property X-Consumer-Department: failed to match pattern "^\\$.*" with "department"
--- no_error_log
[error]



=== TEST 4: valid schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.attach-consumer-label")
            local ok, err = plugin.check_schema({
                headers = {
                    ["X-Consumer-Department"] = "$department",
                    ["X-Consumer-Company"] = "$company"
                }
            })
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
--- no_error_log
[error]



=== TEST 5: add consumer with labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "labels": {
                        "department": "devops",
                        "company": "api7"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/consumers/jack/credentials/a',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "key": "key-a"
                        }
                    }
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
--- no_error_log
[error]



=== TEST 6: add route with only attach-consumer-label plugin (no key-auth)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "attach-consumer-label": {
                            "_meta": {
                                "disable": false
                            },
                            "headers": {
                                "X-Consumer-Department": "$department",
                                "X-Consumer-Company": "$company"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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
--- no_error_log
[error]



=== TEST 7: access without auth (should not contain consumer labels)
--- request
GET /echo
--- response_headers
!X-Consumer-Department
!X-Consumer-Company
--- no_error_log
[error]



=== TEST 8: add route with attach-consumer-label plugin (with key-auth)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "key-auth": {},
                        "attach-consumer-label": {
                            "headers": {
                                "X-Consumer-Department": "$department",
                                "X-Consumer-Company": "$company",
                                "X-Consumer-Role": "$role"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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
--- no_error_log
[error]



=== TEST 9: access with auth (should contain consumer labels headers, but no x-consumer-role)
--- request
GET /echo
--- more_headers
apikey: key-a
X-Consumer-Role: admin
--- response_headers
X-Consumer-Company: api7
X-Consumer-Department: devops
!X-Consumer-Role
--- no_error_log
[error]



=== TEST 10: modify consumer without labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack"
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
--- no_error_log
[error]



=== TEST 11: access with auth (should not contain headers because consumer has no labels)
--- request
GET /echo
--- more_headers
apikey: key-a
--- response_headers
!X-Consumer-Company
!X-Consumer-Department
--- noerror_log
[error]



=== TEST 12: modify consumer with labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "labels": {
                        "department": "devops",
                        "company": "api7"
                    }
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
--- no_error_log
[error]



=== TEST 13: modify route without attach-consumer-label plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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
--- no_error_log
[error]



=== TEST 14: add global rule with attach-consumer-label plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "attach-consumer-label": {
                            "headers": {
                                "X-Global-Consumer-Department": "$department",
                                "X-Global-Consumer-Company": "$company"
                            }
                        }
                    }
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
--- no_error_log
[error]



=== TEST 15: access with auth (should contain expected consumer labels headers)
--- request
GET /echo
--- more_headers
apikey: key-a
--- response_headers
X-Global-Consumer-Company: api7
X-Global-Consumer-Department: devops
--- no_error_log
[error]
