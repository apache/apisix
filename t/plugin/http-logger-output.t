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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: test http-logger have correct output
--- http_config
    lua_shared_dict saved 10m;
--- config
    lua_need_request_body on;
    location /mockpost {
        content_by_lua_block {
            local saved = ngx.shared.saved
            local data = ngx.req.get_body_data()
            ngx.say(data)
            local _, err = saved:set("data", data)
            if err then
                ngx.say(err)
            end
            ngx.say("ok")
        }
    }

    location /mockget {
        content_by_lua_block {
            ngx.sleep(1) -- wait for batch process finished
            local saved = ngx.shared.saved
            ngx.say(saved:get("data"))
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:1984/mockpost",
                                    "batch_max_size": 1
                                }
                        },
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "httpbin.org:80": 1
                            }
                        },
                        "uri": "/get"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": {
                            "host": "$host",
                            "@timestamp": "$time_iso8601",
                            "client_ip": "$remote_addr"
                        }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- pipelined_requests eval
[
"POST /mockpost\nfoo=bar",
"GET /mockget",
"GET /t",
"GET /get",
"GET /mockget"
]
--- response_body_like eval
[
"foo=bar\nok",
"foo=bar",
"passed\npassed",
"",
"\"host\":\"httpbin.org\""
]
--- no_error_log
[error]
