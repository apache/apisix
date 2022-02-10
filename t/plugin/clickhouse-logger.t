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

log_level("info");
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

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10420;
        location /clickhouse-logger/test {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.ERR, "clickhouse body: ", data)
                ngx.say("ok")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: Full configuration verification
--- yaml_config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({timeout = 3,
                                                 retry_delay = 1,
                                                 batch_max_size = 500,
                                                 user = "default",
                                                 password = "a",
                                                 database = "default",
                                                 logtable = "t",
                                                 endpoint_addr = "http://127.0.0.1:10420/clickhouse-logger/test",
                                                 max_retry_count = 1,
                                                 name = "clickhouse logger",
                                                 ssl_verify = false
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
--- yaml_config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({user = "default",
                                                 password = "a",
                                                 database = "default",
                                                 logtable = "t",
                                                 endpoint_addr = "http://127.0.0.1:10420/clickhouse-logger/test"
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
--- yaml_config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({user = "default",
                                                 password = "a",
                                                 database = "default",
                                                 logtable = "t"
                                                 })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
property "endpoint_addr" is required



=== TEST 4: add plugin on routes
--- yaml_config
apisix:
    node_listen: 1984
    admin_key: null
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
                                "endpoint_addr": "http://127.0.0.1:10420/clickhouse-logger/test"
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
                    "action":"set",
                    "node":{
                        "value":{
                            "uri":"/opentracing",
                            "upstream":{
                                "scheme":"http",
                                "nodes":{
                                    "127.0.0.1:1982":1
                                }
                            },
                            "plugins":{
                                "clickhouse-logger":{
                                    "batch_max_size":1000,
                                    "max_retry_count":0,
                                    "retry_delay":1,
                                    "ssl_verify":true,
                                    "endpoint_addr":"http://127.0.0.1:10420/clickhouse-logger/test",
                                    "password":"a",
                                    "buffer_duration":60,
                                    "timeout":3,
                                    "user":"default",
                                    "name":"clickhouse-logger",
                                    "database":"default",
                                    "logtable":"t",
                                    "inactive_timeout":5
                                }
                            },
                            "id":"1"
                        },
                        "key":"/apisix/routes/1"
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



=== TEST 5: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log_out
clickhouse body:
--- wait: 5
