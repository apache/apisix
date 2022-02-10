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

workers(3);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: continue to get nacos data after failure in a service
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  nacos:
      host:
        - "http://127.0.0.1:20999"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      weight: 1
      timeout:
        connect: 2000
        send: 2000
        read: 5000
--- apisix_yaml
routes:
  -
    uri: /hello_
    upstream:
      service_name: NOT-NACOS
      discovery_type: nacos
      type: roundrobin
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
--- http_config
    server {
        listen 20999;

        location / {
            access_by_lua_block {
                if not package.loaded.hit then
                    package.loaded.hit = true
                    ngx.exit(502)
                end
            }
            proxy_pass http://127.0.0.1:8858;
        }
    }
--- request
GET /hello
--- response_body_like eval
qr/server [1-2]/
--- error_log
err:status = 502



=== TEST 2: test complex host
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://nacos:nacos#!&[]()*@127.0.0.1:8858"
      fetch_interval: 1
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin

#END
--- request
GET /hello
--- timeout: 10
--- error_code_like: ^(?:50\d)$
--- error_log
nacos login fail



=== TEST 3: same service is registered in route, service and upstream, de-duplicate
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      fetch_interval: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

           -- use nacos-service5
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream": {
                        "service_name": "APISIX-NACOS",
                        "discovery_type": "nacos",
                        "scheme": "http",
                        "type": "roundrobin",
                        "discovery_args": {
                          "namespace_id": "test_ns",
                          "group_name": "test_group"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            -- use nacos-service7
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "scheme": "http",
                        "discovery_type": "nacos",
                        "pass_host": "pass",
                        "service_name": "APISIX-NACOS",
                        "discovery_args": {
                          "namespace_id": "test_ns",
                          "group_name": "test_group"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "scheme": "http",
                    "discovery_type": "nacos",
                    "pass_host": "pass",
                    "service_name": "APISIX-NACOS",
                    "discovery_args": {
                    "namespace_id": "test_ns",
                    "group_name": "test_group"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.sleep(1.5)

            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local dump_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/discovery/nacos/dump"
            local res, err = httpc:request_uri(dump_uri, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end

            local body = json_decode(res.body)
            local services = body.services
            local service = services["test_ns"]["test_group"]["APISIX-NACOS"]
            local number = table.getn(service)
            ngx.say(number)
        }
    }
--- response_body
1
