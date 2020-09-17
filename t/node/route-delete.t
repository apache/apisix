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

=== TEST 1: create 130 routes + delete them
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            for i = 1, 130 do
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

            for i = 1, 130 do
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

            for i = 1, 130 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_DELETE
                )
            end

            for i = 1, 130 do
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

            for i = 1, 130 do
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
--- grep_error_log eval
qr/\w+ (data by key: 126)/
--- grep_error_log_out
insert data by key: 126
update data by key: 126
delete data by key: 126
insert data by key: 126
delete data by key: 126
--- timeout: 20
