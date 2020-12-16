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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_host_uri'
    admin_key: null
_EOC_

run_tests();

__DATA__

=== TEST 1: default enable route(id: 1) with uri match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
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



=== TEST 2: hit route
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 3: disable route
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local data = {status = 0}

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "status": 0
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
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



=== TEST 4: route not found, failed by disable
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 5: default enable route(id: 1) with host_uri match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
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
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: hit route
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 7: disable route
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local data = {status = 0}

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                core.json.encode(data),
                [[{
                    "node": {
                        "value": {
                            "status": 0
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: route not found, failed by disable
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: foo.com
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- no_error_log
[error]



=== TEST 9: specify an invalid status value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "status": 100,
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"invalid configuration: property \\"status\\" validation failed: matches non of the enum values"\}/
--- no_error_log
[error]



=== TEST 10: compatible with old route data in etcd which not has status
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/routes/1", core.json.decode([[{
                    "uri": "/hello",
                    "priority": 0,
                    "id": "1",
                    "upstream": {
                        "hash_on": "vars",
                        "pass_host": "pass",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]))  ---mock old route data in etcd
            if res.status >= 300 then
                res.status = code
            end
            ngx.print(require("toolkit.json").encode(res.body))
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- response_body_unlike eval
qr/status/
--- no_error_log
[error]



=== TEST 11: hit route(old route data in etcd)
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
