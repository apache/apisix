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
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: Verify consumer plugin update takes effect immediately
--- extra_yaml_config
nginx_config:
  worker_processes: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local http = require("resty.http")

            -- 1. Create route with key-auth plugin
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.org:80": 1
                        }
                    },
                    "plugins": {
                        "key-auth": {
                            "query": "apikey"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("Route creation failed: " .. body)
                return
            end

            -- 2. Create consumer jack
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("Consumer creation failed: " .. body)
                return
            end

            -- 3. Create credentials for jack
            code, body = t('/apisix/admin/consumers/jack/credentials/auth-one',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("Credential creation failed: " .. body)
                return
            end
            ngx.sleep(0.5)  -- wait for etcd to sync
            -- 4. Verify valid request succeeds
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:"..ngx.var.server_port.."/anything?apikey=auth-one",
                { method = "GET" }
            )
            if not res then
                ngx.say("Request failed: ", err)
                return
            end
            
            if res.status ~= 200 then
                ngx.say("Unexpected status: ", res.status)
                ngx.say(res.body)
                return
            end

            -- 5. Update consumer with fault-injection plugin
            code, body = t('/apisix/admin/consumers/jack',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 400,
                                "body": "abort"
                            }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("Consumer update failed: " .. body)
                return
            end

            -- 6. Verify all requests return 400
            for i = 1, 5 do
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:"..ngx.var.server_port.."/anything?apikey=auth-one",
                    { method = "GET" }
                )
                if not res then
                    ngx.say(i, ": Request failed: ", err)
                    return
                end
                
                if res.status ~= 400 then
                    ngx.say(i, ": Expected 400 but got ", res.status)
                    return
                end
                
                if res.body ~= "abort" then
                    ngx.say(i, ": Unexpected response body: ", res.body)
                    return
                end
            end

            ngx.say("All requests aborted as expected")
        }
    }
--- request
GET /t
--- response_body
All requests aborted as expected
--- error_log
--- no_error_log
[error]
[alert]
