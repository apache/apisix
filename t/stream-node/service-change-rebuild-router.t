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

no_long_string();
no_shuffle();
log_level('info');
no_root_location();

run_tests();

__DATA__

=== TEST 1: setup - create service and stream_route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code, body = t('/apisix/admin/stream_routes/99',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "service_id": 99
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



=== TEST 2: service status update (disable) triggers router rebuild
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local function try_stream()
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("127.0.0.1", 1985)
                if not ok then
                    return nil, "connect failed: " .. err
                end
                local ok, err = sock:send("mmm")
                if not ok then
                    sock:close()
                    return nil, "send failed: " .. err
                end
                local data, err = sock:receive("*l")
                sock:close()
                return data, err
            end

            -- Route 99 and service 99 both exist.
            -- First stream connection should succeed.
            local data, err = try_stream()
            if not data then
                ngx.say("FAIL: route not matched initially: ", err)
                return
            end
            ngx.say("before disable: ", data)

            -- Disable the service
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    },
                    "status": 0
                }]]
            )
            if code >= 300 then
                ngx.say("failed to disable service: ", code)
                return
            end

            -- Retry until the router picks up the service status change
            local data2
            for i = 1, 20 do
                ngx.sleep(0.1)
                data2, _ = try_stream()
                if not data2 then
                    break
                end
            end
            if data2 then
                ngx.say("FAIL: route still matched after service disabled: ", data2)
                return
            end
            ngx.say("after disable: route not matched")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
before disable: hello world
after disable: route not matched
--- error_log
match(): not hit any route



=== TEST 3: service re-enable triggers router rebuild
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local function try_stream()
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("127.0.0.1", 1985)
                if not ok then
                    return nil, "connect failed: " .. err
                end
                local ok, err = sock:send("mmm")
                if not ok then
                    sock:close()
                    return nil, "send failed: " .. err
                end
                local data, err = sock:receive("*l")
                sock:close()
                return data, err
            end

            -- Service 99 is disabled (from TEST 2).
            -- First connection should not match.
            local data, _ = try_stream()
            if data then
                ngx.say("FAIL: route matched while service disabled: ", data)
                return
            end
            ngx.say("before enable: route not matched")

            -- Re-enable the service
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    },
                    "status": 1
                }]]
            )
            if code >= 300 then
                ngx.say("failed to enable service: ", code)
                return
            end

            -- Retry until the router picks up the service status change
            local data2
            for i = 1, 20 do
                ngx.sleep(0.1)
                data2, _ = try_stream()
                if data2 then
                    break
                end
            end
            if not data2 then
                ngx.say("FAIL: route still not matched after service re-enabled")
                return
            end
            ngx.say("after enable: ", data2)
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
before enable: route not matched
after enable: hello world
--- error_log
match(): not hit any route



=== TEST 4: service delete then recreate triggers router rebuild
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local function try_stream()
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("127.0.0.1", 1985)
                if not ok then
                    return nil, "connect failed: " .. err
                end
                local ok, err = sock:send("mmm")
                if not ok then
                    sock:close()
                    return nil, "send failed: " .. err
                end
                local data, err = sock:receive("*l")
                sock:close()
                return data, err
            end

            -- Service 99 is active (from TEST 3).
            -- First connection should match.
            local data, err = try_stream()
            if not data then
                ngx.say("FAIL: route not matched initially: ", err)
                return
            end
            ngx.say("before delete: ", data)

            -- Delete the service
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_DELETE
            )
            if code >= 300 then
                ngx.say("failed to delete service: ", code)
                return
            end

            -- Retry until the router picks up the service deletion
            local data2
            for i = 1, 20 do
                ngx.sleep(0.1)
                data2, _ = try_stream()
                if not data2 then
                    break
                end
            end
            if data2 then
                ngx.say("FAIL: route still matched after service deleted: ", data2)
                return
            end
            ngx.say("after delete: route not matched")

            -- Recreate the service
            code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("failed to recreate service: ", code)
                return
            end

            -- Retry until the router picks up the new service
            local data3
            for i = 1, 20 do
                ngx.sleep(0.1)
                data3, _ = try_stream()
                if data3 then
                    break
                end
            end
            if not data3 then
                ngx.say("FAIL: route not matched after service recreated")
                return
            end
            ngx.say("after recreate: ", data3)
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
before delete: hello world
after delete: route not matched
after recreate: hello world
--- error_log
failed to fetch service configuration by id: 99



=== TEST 5: cleanup
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/stream_routes/99', ngx.HTTP_DELETE)
            t('/apisix/admin/services/99', ngx.HTTP_DELETE)
            ngx.say("cleaned up")
        }
    }
--- request
GET /t
--- response_body
cleaned up
