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
log_level('warn');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: dynamic host based discovery
--- extra_yaml_config
nginx_config:
    worker_processes: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local discovery = require("apisix.discovery.init").discovery
            local core = require("apisix.core")
            discovery.demo_discover = {
                nodes = function()
                    local demo_nodes_tab = {
                        a = { host = "127.0.0.1", port = 1111 },
                        b = { host = "127.0.0.1", port = 2222 }
                    }
                    local host = ngx.var.host
                    local service_id = host:match("([^.]+).myhost.com")
                    local demo_node = demo_nodes_tab[service_id]

                    local node_list = core.table.new(1, 0)
                    core.table.insert(node_list, {
                        host = demo_node.host,
                        port = tonumber(demo_node.port),
                        weight = 100,
                    })

                    return node_list
                end
            }

            local code, body = t('/apisix/admin/services/',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "demo_service",
                    "name": "demo_service",
                    "upstream": {
                        "discovery_type": "demo_discover",
                        "service_name": "demo_service",
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end

            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/',
                 ngx.HTTP_PUT,
                 [[{
                    "id": "demo_route",
                    "name": "demo_route",
                    "uri": "/*",
                    "hosts":[
                    "*.myhost.com"
                    ],
                    "service_id": "demo_service"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end

            ngx.sleep(0.5)

            local hosts = {
                "a.myhost.com",
                "a.myhost.com",
                "b.myhost.com",
                "b.myhost.com",
                "a.myhost.com",
                "b.myhost.com",
                "b.myhost.com",
                "a.myhost.com",
                "b.myhost.com",
                "a.myhost.com",
            }

            for i, url_host in ipairs(hosts) do
                local http = require "resty.http"
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/"
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false, headers = {
                    ["Host"] = url_host
                }})
            end
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/upstream: \S+, host: \S+/
--- grep_error_log_out
upstream: "http://127.0.0.1:1111/", host: "a.myhost.com"
upstream: "http://127.0.0.1:1111/", host: "a.myhost.com"
upstream: "http://127.0.0.1:2222/", host: "b.myhost.com"
upstream: "http://127.0.0.1:2222/", host: "b.myhost.com"
upstream: "http://127.0.0.1:1111/", host: "a.myhost.com"
upstream: "http://127.0.0.1:2222/", host: "b.myhost.com"
upstream: "http://127.0.0.1:2222/", host: "b.myhost.com"
upstream: "http://127.0.0.1:1111/", host: "a.myhost.com"
upstream: "http://127.0.0.1:2222/", host: "b.myhost.com"
upstream: "http://127.0.0.1:1111/", host: "a.myhost.com"
