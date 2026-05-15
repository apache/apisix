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
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: setup a service and a stream_route bound to it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
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
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: stream connection routes through the service upstream
--- stream_request
mmm
--- stream_response
hello world



=== TEST 3: update the service (no change to the stream_route itself)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/99',
                ngx.HTTP_PUT,
                [[{
                    "name": "svc99",
                    "desc": "updated",
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: stream routing still works after the service version changes
--- stream_request
mmm
--- stream_response
hello world



=== TEST 5: delete the stream_route, then the service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/stream_routes/99', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return
            end
            code = t('/apisix/admin/services/99', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 6: stream connection no longer matches any route
--- stream_enable
--- stream_response
--- error_log
not hit any route
