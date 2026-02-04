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

# make sure we exercise privileged agent + workers
workers(4);

add_block_preprocessor(sub {
    my ($block) = @_;

    # default request target for blocks that don't specify one
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

# base config for tests
our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  nacos:
    # first test will point to an unreachable host; second test will override
    host:
      - "http://127.0.0.1:20999"
    prefix: "/nacos/v1/"
    fetch_interval: 1
    weight: 1
    timeout:
      connect: 2000
      send: 2000
      read: 5000
_EOC_

run_tests();

__DATA__

=== TEST 1: only privileged agent should attempt nacos fetches (unreachable host)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /noop
    upstream:
      service_name: NOT-USED
      discovery_type: nacos
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            -- wait a bit for APISIX init timers to run
            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/failed to fetch nacos registry from all hosts/
--- grep_error_log_out eval
"failed to fetch nacos registry from all hosts\n" x 3

=== TEST 2: workers must resolve nodes across admin update / cache versioning
--- yaml_config eval: $::yaml_config
--- extra_yaml_config
# override discovery host to a local fake server (defined below) for this test
discovery:
  nacos:
    host:
      - "http://127.0.0.1:20998"
    fetch_interval: 1
    prefix: "/nacos/v1/"
    weight: 1
    timeout:
      connect: 2000
      send: 2000
      read: 5000
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
--- http_config
    server {
        listen 20998;

        # Simulate minimal Nacos service list API.
        # Each call to /nacos/v1/ns/instance/list will return a static set of instances.
        # We also expose /health to allow test code to check the fake server is up.
        location /nacos/v1/ns/instance/list {
            content_by_lua_block {
                local args = ngx.req.get_uri_args()
                local svc = args.serviceName or args.serviceName or "APISIX-NACOS"
                -- return a simple instances list suiting APISIX's parser
                ngx.header.content_type = "application/json"
                ngx.say([[
{
  "hosts": [
    {"ip":"127.0.0.1","port":30511,"weight":1},
    {"ip":"127.0.0.1","port":30512,"weight":1}
  ],
  "dom": "]] .. svc .. [["
}
]])
            }
        }

        location /health {
            return 200 'ok';
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

            -- Wait for APISIX to initialize and privileged agent to fetch registry
            ngx.sleep(2)

            -- First ensure that requests to the route are routed to one of the upstream nodes
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello")
            if not res then
                ngx.say("FAIL: request failed: ", err)
                return
            end
            local body = (res.body or ""):gsub("%s+$", "")
            if not (body == "server 1" or body == "server 2") then
                ngx.say("FAIL: unexpected body: ", body)
                return
            end

            -- Now simulate a config change that should bump config version / trigger reload behavior.
            -- Update a dummy route (this triggers admin write & config reload path).
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/noop2",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": [{"host":"127.0.0.1","port":1980,"weight":1}]
                    }
                }]]
                )
            if code >= 300 then
                ngx.say("FAIL: admin update returned ", code)
                return
            end

            -- wait a bit for config propagation
            ngx.sleep(1)

            -- Make sure workers still resolve the nacos-discovered nodes after the admin update
            res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello")
            if not res then
                ngx.say("FAIL: request failed after update: ", err)
                return
            end
            body = (res.body or ""):gsub("%s+$", "")
            if body == "server 1" or body == "server 2" then
                ngx.say("PASS")
            else
                ngx.say("FAIL: unexpected body after update: ", body)
            end
        }
    }
--- request
GET /t
--- response_body
PASS
