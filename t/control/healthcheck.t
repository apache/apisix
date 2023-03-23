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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: upstreams
--- ONLY
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
upstreams:
    - nodes:
        "127.0.0.1:1980": 1
        "127.0.0.2:1988": 1
      type: roundrobin
      id: 1
      checks:
        active:
            http_path: "/status"
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})

            ngx.sleep(2.2)
            local check_nodes = function(nodes)
                assert(#nodes == 2, "invalid number of nodes")

                assert(nodes[1].ip == "127.0.0.1", "invalid ip")
                assert(nodes[1].port == 1980, "invalid port")
                assert(nodes[1].status == "healthy", "invalid status")

                assert(nodes[2].ip == "127.0.0.2", "invalid ip")
                assert(nodes[2].port == 1988, "invalid port")
                assert(nodes[2].status == "unhealthy", "invalid status")
            end

            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            res = json.decode(res)
            assert(#res == 1, "invalid number of results")
            table.sort(res[1].nodes, function(a, b)
                return a.ip < b.ip
            end)
            check_nodes(res[1].nodes)

            local code, body, res = t.test('/v1/healthcheck/upstreams/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res.nodes, function(a, b)
                return a.ip < b.ip
            end)

            check_nodes(res.nodes)
        }
    }
--- grep_error_log eval
qr/unhealthy TCP increment \(.+\) for '[^']+'/
--- grep_error_log_out
unhealthy TCP increment (1/2) for '(127.0.0.2:1988)'
unhealthy TCP increment (2/2) for '(127.0.0.2:1988)'



=== TEST 2: routes
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /hello
    upstream:
      nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1988": 1
      type: roundrobin
      checks:
        active:
            http_path: "/status"
            host: "127.0.0.1"
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})

            ngx.sleep(2.2)

            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res[1].nodes, function(a, b)
                return a.port < b.port
            end)
            ngx.say(json.encode(res))

            local code, body, res = t.test('/v1/healthcheck/routes/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res.nodes, function(a, b)
                return a.port < b.port
            end)
            ngx.say(json.encode(res))
        }
    }
--- grep_error_log eval
qr/unhealthy TCP increment \(.+\) for '[^']+'/
--- grep_error_log_out
unhealthy TCP increment (1/2) for '127.0.0.1(127.0.0.1:1988)'
unhealthy TCP increment (2/2) for '127.0.0.1(127.0.0.1:1988)'
--- response_body
[{"healthy_nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1}],"name":"upstream#/routes/1","nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1},{"host":"127.0.0.1","port":1988,"priority":0,"weight":1}],"src_id":"1","src_type":"routes"}]
{"healthy_nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1}],"name":"upstream#/routes/1","nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1},{"host":"127.0.0.1","port":1988,"priority":0,"weight":1}],"src_id":"1","src_type":"routes"}



=== TEST 3: services
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  - id: 1
    service_id: 1
    uris:
        - /hello

services:
  -
    id: 1
    upstream:
      nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1988": 1
      type: roundrobin
      checks:
        active:
            http_path: "/status"
            host: "127.0.0.1"
            port: 1988
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})

            ngx.sleep(2.2)

            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res[1].nodes, function(a, b)
                return a.port < b.port
            end)
            ngx.say(json.encode(res))

            local code, body, res = t.test('/v1/healthcheck/services/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res.nodes, function(a, b)
                return a.port < b.port
            end)
            ngx.say(json.encode(res))
        }
    }
--- grep_error_log eval
qr/unhealthy TCP increment \(.+\) for '[^']+'/
--- grep_error_log_out
unhealthy TCP increment (1/2) for '127.0.0.1(127.0.0.1:1988)'
unhealthy TCP increment (2/2) for '127.0.0.1(127.0.0.1:1988)'
--- response_body
[{"healthy_nodes":{},"name":"upstream#/services/1","nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1},{"host":"127.0.0.1","port":1988,"priority":0,"weight":1}],"src_id":"1","src_type":"services"}]
{"healthy_nodes":{},"name":"upstream#/services/1","nodes":[{"host":"127.0.0.1","port":1980,"priority":0,"weight":1},{"host":"127.0.0.1","port":1988,"priority":0,"weight":1}],"src_id":"1","src_type":"services"}



=== TEST 4: no checkers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            ngx.print(res)
        }
    }
--- response_body
{}



=== TEST 5: no checker
--- request
GET /v1/healthcheck/routes/1
--- error_code: 404
--- response_body
{"error_msg":"routes[1] not found"}



=== TEST 6: invalid src type
--- request
GET /v1/healthcheck/route/1
--- error_code: 400
--- response_body
{"error_msg":"invalid src type route"}
