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
workers(4);

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      weight: 1
      timeout:
        connect: 2000
        send: 2000
        read: 5000

_EOC_

our $yaml_auth_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  nacos:
      host:
        - "http://nacos:nacos\@127.0.0.1:8848"
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


=== TEST 24: hit with namespace_id and group_name
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      fetch_interval: 1
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello",
]
--- response_body_like eval
[
    qr/server [1-2]/,
    qr/server [1-2]/,
]
--- timeout: 10



=== TEST 25: same namespace_id and service_name, different group_name
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

            -- use nacos-service6
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello1",
                    "upstream": {
                        "service_name": "APISIX-NACOS",
                        "discovery_type": "nacos",
                        "type": "roundrobin",
                        "discovery_args": {
                          "namespace_id": "test_ns",
                          "group_name": "test_group2"
                        }
                    },
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/hello"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            ngx.sleep(1.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri1, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end
            ngx.say(res.body)

            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            res, err = httpc:request_uri(uri2, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body
server 1
server 3
--- timeout: 10
