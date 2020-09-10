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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret"})
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
--- no_error_log
[error]



=== TEST 2: missing access_key_secret
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "access_key_secret" is required
done
--- no_error_log
[error]



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your_project", logstore = "your_logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret", timeout = "10"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
done
--- no_error_log
[error]



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "100.100.99.135",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "sls-logger": {
                                    "host": "100.100.99.135",
                                    "port": 10009,
                                    "project": "your_project",
                                    "logstore": "your_logstore",
                                    "access_key_id": "your_access_key_id",
                                    "access_key_secret": "your_access_key_secret",
                                    "timeout": 30000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 5: access
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
--- wait: 1
