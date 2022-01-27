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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: Full configuration verification
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({
                "timeout": 3,
                "retry_delay": 1,
                "batch_max_size": 500,
                "user": "default",
                "password": "a",
                "database": "default",
                "logtable": "t",
                "endpoint_addr": "http://127.0.0.1:8123",
                "max_retry_count": 1,
                "name": "clickhouse logger"
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: Basic configuration verification
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({
                "user": "default",
                "password": "a",
                "database": "default",
                "logtable": "t",
                "endpoint_addr": "http://127.0.0.1:8123"
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 3: auth configure undefined
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({
                log_id = "syslog",
                max_retry_count = 0,
                retry_delay = 1,
                buffer_duration = 60,
                inactive_timeout = 10,
                batch_max_size = 100,
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
value should match only one schema, but matches none



=== TEST 4: add plugin on routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "clickhouse-logger": {
                                "user": "default",
                                "password": "a",
                                "database": "default",
                                "logtable": "t",
                                "endpoint_addr": "http://127.0.0.1:8123"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "clickhouse-logger": {
                                    "user": "default",
                                    "password": "a",
                                    "database": "default",
                                    "logtable": "t",
                                    "endpoint_addr": "http://127.0.0.1:8123"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 5: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[http logger] successfully processed the entries
--- wait: 0.5
