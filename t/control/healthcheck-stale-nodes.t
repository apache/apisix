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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: deleted node must not appear in the health check control API
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local http = require "resty.http"

            local code = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": {"127.0.0.1:1980": 1, "127.0.0.1:1981": 1},
                    "checks": {
                        "active": {
                            "type": "tcp",
                            "timeout": 1,
                            "healthy": {"interval": 1, "successes": 1},
                            "unhealthy": {"interval": 1, "tcp_failures": 1}
                        }
                    }
                }]])
            if code >= 300 then ngx.say("create upstream failed: ", code) return end

            code = t.test('/apisix/admin/routes/1', ngx.HTTP_PUT,
                [[{"uri": "/hello", "upstream_id": "1"}]])
            if code >= 300 then ngx.say("create route failed: ", code) return end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            http.new():request_uri(uri, {method = "GET"})
            ngx.sleep(3)

            -- both nodes are registered with the checker
            local _, _, res = t.test('/v1/healthcheck/upstreams/1', ngx.HTTP_GET)
            res = json.decode(res)
            ngx.say("before delete: ", #res.nodes, " nodes")

            -- remove 127.0.0.1:1981 from the upstream
            code = t.test('/apisix/admin/upstreams/1/nodes', ngx.HTTP_PATCH,
                [[{"127.0.0.1:1980": 1}]])
            if code >= 300 then ngx.say("patch failed: ", code) return end

            http.new():request_uri(uri, {method = "GET"})
            ngx.sleep(3)

            -- the deleted node must be gone, the kept node must remain
            local _, _, res2 = t.test('/v1/healthcheck/upstreams/1', ngx.HTTP_GET)
            res2 = json.decode(res2)
            local stale, kept = false, false
            for _, node in ipairs(res2.nodes) do
                if node.ip == "127.0.0.1" and node.port == 1981 then
                    stale = true
                end
                if node.ip == "127.0.0.1" and node.port == 1980 then
                    kept = true
                end
            end
            ngx.say("after delete: stale=", stale, " kept=", kept)
        }
    }
--- request
GET /t
--- response_body
before delete: 2 nodes
after delete: stale=false kept=true
--- timeout: 10
