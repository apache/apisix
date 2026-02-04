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

=== TEST 1: use variable in count and time_window with default value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 '{\
                    "uri": "/ai",\
                    "plugins": {\
                        "ai-proxy-multi": {\
                            "fallback_strategy": "instance_health_and_rate_limiting",\
                            "instances": [\
                                {\
                                    "name": "deepseek",\
                                    "provider": "openai",\
                                    "weight": 1,\
                                    "priority": 1,\
                                    "auth": {\
                                        "header": {\
                                            "Authorization": "Bearer token"\
                                        }\
                                    },\
                                    "override": {\
                                        "endpoint": "http://localhost:16724"\
                                    }\
                                },\
                                {\
                                    "name": "openai",\
                                    "provider": "openai",\
                                    "weight": 1,\
                                    "priority": 0,\
                                    "auth": {\
                                        "header": {\
                                            "Authorization": "Bearer token"\
                                        }\
                                    },\
                                    "override": {\
                                        "endpoint": "http://localhost:16724"\
                                    }\
                                }\
                            ],\
                            "ssl_verify": false\
                        },\
                        "ai-rate-limiting": {\
                            "limit": "${http_count ?? 10}",\
                            "time_window": "${http_time_window ?? 60}",\
                            "instances": [\
                                {\
                                    "name": "openai",\
                                    "limit": "${http_openai_count ?? 20}",\
                                    "time_window": "${http_time_window ?? 60}"\
                                }\
                            ]\
                        }\
                    },\
                    "upstream": {\
                        "type": "roundrobin",\
                        "nodes": {\
                            "canbeanything.com": 1\
                        }\
                    }\
                }'
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



=== TEST 2: request with default variable values
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")

            local test_cases = {
                { code = 200 },
                { code = 200 },
                { code = 200 },
                { code = 503 },
            }

            local httpc = http.new()
            for i, case in ipairs(test_cases) do
                local res = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/ai",
                    {
                        method = "POST",
                        body = '{\
                            "messages": [\
                                { "role": "system", "content": "You are a mathematician" },\
                                { "role": "user", "content": "What is 1+1?" }\
                            ]\
                        }',
                        headers = {
                            ["Content-Type"] = "application/json",
                        }
                    }
                )
                if res.status ~= case.code then
                    ngx.say( i  .. "th request should return " .. case.code .. ", but got " .. res.status)
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
passed
--- grep_error_log eval
qr/picked instance: [^,]+/
--- grep_error_log_out
picked instance: deepseek
picked instance: openai
picked instance: openai
picked instance: nil
