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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10420;

        location /clickhouse-logger/test1 {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.WARN, "clickhouse body: ", data)
                for k, v in pairs(headers) do
                    ngx.log(ngx.WARN, "clickhouse headers: " .. k .. ":" .. v)
                end
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
                                                 endpoint_addr = "http://127.0.0.1:1980/clickhouse_logger_server",
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
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({user = "default",
                                                 password = "a",
                                                 database = "default",
                                                 logtable = "t",
                                                 endpoint_addr = "http://127.0.0.1:1980/clickhouse_logger_server"
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
                                "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                                "batch_max_size":1,
                                "inactive_timeout":1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
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



=== TEST 5: add plugin on routes using multi clickhouse-logger
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
                                "password": "",
                                "database": "default",
                                "logtable": "test",
                                "endpoint_addrs": ["http://127.0.0.1:8123",
                                                  "http://127.0.0.1:8124"],
                                "batch_max_size":1,
                                "inactive_timeout":1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 200
--- response_body
passed



=== TEST 6: hit route
--- request
GET /opentracing
--- error_code: 200
--- wait: 5



=== TEST 7: get log
--- exec
echo "select * from default.test" | curl 'http://localhost:8123/' --data-binary @-
echo "select * from default.test" | curl 'http://localhost:8124/' --data-binary @-
--- response_body_like
.*127.0.0.1.*1.*



=== TEST 8: to show that different endpoints will be chosen randomly
--- config
    location /t {
        content_by_lua_block {
            local code_count = {}
            local t = require("lib.test_admin").test
            for i = 1, 12 do
                local code, body = t('/opentracing', ngx.HTTP_GET)
                if code ~= 200 then
                    ngx.say("code: ", code, " body: ", body)
                end
                code_count[code] = (code_count[code] or 0) + 1
            end

            local code_arr = {}
            for code, count in pairs(code_count) do
                table.insert(code_arr, {code = code, count = count})
            end

            ngx.say(require("toolkit.json").encode(code_arr))
            ngx.exit(200)
        }
    }
--- response_body
[{"code":200,"count":12}]
--- error_log
sending a batch logs to http://127.0.0.1:8123
sending a batch logs to http://127.0.0.1:8124



=== TEST 9: use single clickhouse server
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
                                "password": "",
                                "database": "default",
                                "logtable": "test",
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



=== TEST 10: hit route
--- request
GET /opentracing
--- error_code: 200
--- wait: 5



=== TEST 11: get log
--- exec
echo "select * from default.test" | curl 'http://localhost:8123/' --data-binary @-
--- response_body_like
.*127.0.0.1.*1.*
