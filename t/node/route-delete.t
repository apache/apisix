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

repeat_each(2);
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: clear all routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            for i = 1, 200 do
                t('/apisix/admin/routes/' .. i, ngx.HTTP_DELETE)
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
--- timeout: 5



=== TEST 2: create 106 routes + delete them
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            for i = 1, 106 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            for i = 1, 106 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            for i = 1, 106 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_DELETE
                )
            end

            ngx.sleep(0.5)

            for i = 1, 106 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            for i = 1, 106 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_DELETE
                )
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
--- wait: 1
--- grep_error_log eval
qr/\w+ (data by key: 103)/
--- grep_error_log_out
insert data by key: 103
update data by key: 103
delete data by key: 103
insert data by key: 103
delete data by key: 103
--- timeout: 30
