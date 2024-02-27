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
log_level('info');
run_tests;

__DATA__

=== TEST 1:  create ssl for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: set route, http_statuses: [500, 503]
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "api-breaker": {
                            "break_response_code": 599,
                            "unhealthy": {
                                "http_statuses": [500, 503],
                                "failures": 3
                            },
                            "healthy": {
                                "http_statuses": [200, 206],
                                "successes": 3
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api_breaker"
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



=== TEST 3: trigger
--- exec
curl -k -v -H "Host: test.com" --data-urlencode 'code=200' -G --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 | cat
--- response_body_like
200



=== TEST 4: trigger breaker
--- exec
curl -k -v -H "Host: test.com" -G --data-urlencode 'code=200' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 && \
curl -k -v -H "Host: test.com" -G --data-urlencode 'code=500' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 && \
curl -k -v -H "Host: test.com" -G --data-urlencode 'code=503' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 && \
curl -k -v -H "Host: test.com" -G --data-urlencode 'code=500' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 && \
curl -k -v -H "Host: test.com" -G --data-urlencode 'code=500' --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/api_breaker 2>&1 | cat
--- access_log
"GET /api_breaker?code=200 HTTP/3.0" 200
"GET /api_breaker?code=500 HTTP/3.0" 500
"GET /api_breaker?code=503 HTTP/3.0" 503
"GET /api_breaker?code=500 HTTP/3.0" 500
"GET /api_breaker?code=500 HTTP/3.0" 599
