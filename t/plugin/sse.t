# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
# either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#

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

run_tests();

__DATA__

=== TEST 1: sse plugin with default configuration
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("t.test_funcs")

        -- upstream returns SSE data
        t.set_upstream(function()
            ngx.header["Content-Type"] = "text/plain"
            ngx.say("data: hello from upstream")
        end)

        local route_conf = {
            uri = "/sse",
            plugins = {
                sse = {}
            },
            upstream = {
                type = "roundrobin",
                nodes = {
                    [t.upstream_server_host_1] = 1,
                }
            }
        }
        t.add_route("/t/route/1", route_conf)
        core.response.exit(200)
    }
}
--- request
GET /sse
--- response_headers
Content-Type: text/event-stream; charset=utf-8
X-Accel-Buffering: no
Cache-Control: no-cache
Connection: keep-alive
--- response_body
data: hello from upstream
--- error_code: 200
--- no_error_log
[error]



=== TEST 2: sse plugin with override_content_type = false
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("t.test_funcs")

        -- upstream returns JSON
        t.set_upstream(function()
            ngx.header["Content-Type"] = "application/json"
            ngx.say("{\"message\": \"hello\"}")
        end)

        local route_conf = {
            uri = "/sse_no_override",
            plugins = {
                sse = {
                    override_content_type = false
                }
            },
            upstream = {
                type = "roundrobin",
                nodes = {
                    [t.upstream_server_host_1] = 1,
                }
            }
        }
        t.add_route("/t/route/2", route_conf)
        core.response.exit(200)
    }
}
--- request
GET /sse_no_override
--- response_headers
Content-Type: application/json
X-Accel-Buffering: no
Cache-Control: no-cache
Connection: keep-alive
--- response_body
{"message": "hello"}
--- error_code: 200
--- no_error_log
[error]



=== TEST 3: sse plugin with custom connection and cache-control headers
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("t.test_funcs")

        -- upstream returns SSE data
        t.set_upstream(function()
            ngx.header["Content-Type"] = "text/plain"
            ngx.say("data: hello from upstream")
        end)

        local route_conf = {
            uri = "/sse_custom",
            plugins = {
                sse = {
                    connection_header = "Upgrade",
                    cache_control = "public, max-age=86400"
                }
            },
            upstream = {
                type = "roundrobin",
                nodes = {
                    [t.upstream_server_host_1] = 1,
                }
            }
        }
        t.add_route("/t/route/3", route_conf)
        core.response.exit(200)
    }
}
--- request
GET /sse_custom
--- response_headers
Content-Type: text/event-stream; charset=utf-8
X-Accel-Buffering: no
Cache-Control: public, max-age=86400
Connection: Upgrade
--- response_body
data: hello from upstream
--- error_code: 200
--- no_error_log
[error]



=== TEST 4: route without SSE plugin (negative case)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("t.test_funcs")

        -- upstream returns plain text
        t.set_upstream(function()
            ngx.header["Content-Type"] = "text/plain"
            ngx.say("data: hello from upstream")
        end)

        local route_conf = {
            uri = "/no_sse",
            plugins = {
                -- No SSE plugin here
            },
            upstream = {
                type = "roundrobin",
                nodes = {
                    [t.upstream_server_host_1] = 1,
                }
            }
        }
        t.add_route("/t/route/4", route_conf)
        core.response.exit(200)
    }
}
--- request
GET /no_sse
--- response_headers_unlike
Content-Type: text/event-stream
X-Accel-Buffering: .*
Cache-Control: .*
Connection: .*
--- response_body
data: hello from upstream
--- error_code: 200
--- no_error_log
[error]
