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
    others:
      - name: nacos3
        host:
          - "http://127.0.0.1:8868"
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

=== TEST 1: get APISIX-NACOS info from NACOS - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
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
--- no_error_log
[error, error]



=== TEST 2: error service_name name - no auth
--- yaml_config eval: $::yaml_config
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
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 3: get APISIX-NACOS info from NACOS - auth
--- yaml_config eval: $::yaml_auth_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
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
--- no_error_log
[error, error]



=== TEST 4: error service_name name - auth
--- yaml_config eval: $::yaml_auth_config
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
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 5: get APISIX-NACOS info from NACOS - configured in services
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    service_id: 1
services:
  -
    id: 1
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
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



=== TEST 6: get APISIX-NACOS info from NACOS - configured in upstreams + etcd
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
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": 1
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



=== TEST 7: hit
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



=== TEST 8: get APISIX-NACOS info from NACOS - no auth with namespace
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: test_ns
#END
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



=== TEST 9: error namespace_id - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: err_ns
#END
--- request
GET /hello
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 10: get APISIX-NACOS info from NACOS - configured in services with namespace
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    service_id: 1
services:
  -
    id: 1
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: test_ns
#END
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



=== TEST 11: get APISIX-NACOS info from NACOS - configured in upstreams + etcd with namespace
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
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin",
                    "discovery_args": {
                      "namespace_id": "test_ns"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": 1
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



=== TEST 12: hit with namespace
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



=== TEST 13: get APISIX-NACOS info from NACOS - no auth with group_name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        group_name: test_group
#END
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



=== TEST 14: error group_name - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        group_name: err_group_name
#END
--- request
GET /hello
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 15: get APISIX-NACOS info from NACOS - configured in services with group_name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    service_id: 1
services:
  -
    id: 1
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        group_name: test_group
#END
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



=== TEST 16: get APISIX-NACOS info from NACOS - configured in upstreams + etcd with group_name
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
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin",
                    "discovery_args": {
                      "group_name": "test_group"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": 1
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



=== TEST 17: hit with group_name
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



=== TEST 18: get APISIX-NACOS info from NACOS - no auth with namespace_id and group_name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: test_ns
        group_name: test_group
#END
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



=== TEST 19: error group_name and correct namespace_id - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: test_ns
        group_name: err_group_name
#END
--- request
GET /hello
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 20: error namespace_id and correct group_name - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: err_ns
        group_name: test_group
#END
--- request
GET /hello
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 21: error namespace_id and error group_name - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: err_ns
        group_name: err_group_name
#END
--- request
GET /hello
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 22: get APISIX-NACOS info from NACOS - configured in services with namespace_id and group_name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    service_id: 1
services:
  -
    id: 1
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        namespace_id: test_ns
        group_name: test_group
#END
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



=== TEST 23: get APISIX-NACOS info from NACOS - configured in upstreams + etcd with namespace_id and group_name
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
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin",
                    "discovery_args": {
                      "namespace_id": "test_ns",
                      "group_name": "test_group"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": 1
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



=== TEST 26: same group_name and service_name, different namespace_id
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

            -- use nacos-service7
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello1",
                    "upstream": {
                        "service_name": "APISIX-NACOS",
                        "discovery_type": "nacos",
                        "type": "roundrobin",
                        "discovery_args": {
                          "namespace_id": "test_ns2",
                          "group_name": "test_group"
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
server 4



=== TEST 27: get APISIX-NACOS info from NACOS by nacos name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      discovery_args:
        name: nacos3
        namespace_id: test_ns
        group_name: test_group

      type: roundrobin
#END
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
--- no_error_log
[error, error]
