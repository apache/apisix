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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: http_method_as_scope must not accumulate the request method across requests
--- http_config
    lua_shared_dict mock_perms 1m;
    server {
        listen 10931;
        server_name localhost;

        # mock token endpoint: records the permission(s) it receives, in order.
        location = /token {
            content_by_lua_block {
                ngx.req.read_body()
                local args = ngx.decode_args(ngx.req.get_body_data() or "")
                local perm = args.permission
                if type(perm) == "table" then
                    perm = table.concat(perm, ",")
                end
                perm = perm or ""

                local d = ngx.shared.mock_perms
                local n = d:incr("count", 1, 0)
                d:set("perm_" .. n, perm)

                ngx.status = 200
                ngx.say('{"result":true}')
            }
        }

        # returns the ordered list of permission strings the gateway sent.
        location = /dump {
            content_by_lua_block {
                local d = ngx.shared.mock_perms
                local n = tonumber(d:get("count")) or 0
                local out = {}
                for i = 1, n do
                    out[i] = d:get("perm_" .. i)
                end
                ngx.print(table.concat(out, "\n"))
            }
        }

        # plain upstream for the protected route.
        location / {
            content_by_lua_block {
                ngx.print("UPSTREAM-REACHED")
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/course",
                "plugins": {
                    "authz-keycloak": {
                        "token_endpoint": "http://127.0.0.1:10931/token",
                        "client_id": "course_management",
                        "permissions": ["course_resource"],
                        "lazy_load_paths": false,
                        "http_method_as_scope": true,
                        "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                        "timeout": 3000
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": { "127.0.0.1:10931": 1 }
                }
            }]])
            if code >= 300 then ngx.say("setup route failed: ", code); return end
            ngx.sleep(0.5)

            local function call()
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984/course", {
                    method = "GET",
                    headers = { ["Authorization"] = "Bearer dummy-user-token" },
                })
                if not res then
                    ngx.say("request error: ", tostring(err))
                    return
                end
                if res.status ~= 200 then
                    ngx.say("unexpected status: ", res.status)
                    return
                end
                if res.body ~= "UPSTREAM-REACHED" then
                    ngx.say("unexpected body: ", tostring(res.body))
                    return
                end
            end

            -- two identical GET requests share the cached route conf;
            -- the configured permissions list must not accumulate the
            -- request method across requests.
            call()
            call()

            local httpc = http.new()
            local dump = httpc:request_uri("http://127.0.0.1:10931/dump")
            ngx.say(dump and dump.body or "no dump")
        }
    }
--- request
GET /t
--- response_body
course_resource#GET
course_resource#GET
--- no_error_log
[alert]
