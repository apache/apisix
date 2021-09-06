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
no_root_location();
no_shuffle();
workers(4);

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    client:
      token: \$\{KUBERNETES_CLIENT_TOKEN\}
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN
_EOC_

run_tests();

__DATA__

=== TEST 1: use default parameters
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    client:
      token: ${KUBERNETES_CLIENT_TOKEN}
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN
--- apisix_yaml
routes:
  - uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504



=== TEST 2: use specify parameters
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      host: "127.0.0.1"
      port: "6443"
    client:
      token: "${KUBERNETES_CLIENT_TOKEN}"
nginx_config:
  envs:
  - KUBERNETES_CLIENT_TOKEN
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504




=== TEST 3: use specify environment parameters
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      host: ${KUBERNETES_SERVICE_HOST}
      port: ${KUBERNETES_SERVICE_PORT}
    client:
      token: "${KUBERNETES_CLIENT_TOKEN}"
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504




=== TEST 4: use token_file
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    client:
      token_file: ${KUBERNETES_CLIENT_TOKEN_FILE}
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN_FILE
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504




=== TEST 5: use http
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      schema: http
      host: "127.0.0.1"
      port: "6445"
    client:
      token: ""
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504



=== TEST 6: error service_name  - bad namespace
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: default/kube-dns:dns-tcp
      discovery_type: k8s
      type: roundrobin
#END
--- request
GET /hello
--- error_code: 503



=== TEST 7: error service_name   - bad service
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: kube-systm/notexit:dns-tcp
      discovery_type: k8s
      type: roundrobin
#END
--- request
GET /hello
--- error_code: 503



=== TEST 8: error service_name   - bad port
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: kube-systm/kube-dns:notexit
      discovery_type: k8s
      type: roundrobin
#END
--- request
GET /hello
--- error_code: 503



=== TEST 9: get kube-system/kube-dns:dns-tcp from k8s - configured in routes
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      timeout:
        connect: 0.5
        send : 1
        read : 1
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
#END
--- request
GET /hello
--- error_code: 504



=== TEST 10: get kube-system/kube-dns:dns-tcp from k8s - configured in services
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
      service_name : kube-system/kube-dns:dns-tcp
      type: roundrobin
      discovery_type: k8s
      timeout:
        connect: 0.5
        send : 1
        read : 1
#END
--- request
GET /hello
--- error_code: 504



=== TEST 11: get kube-system/kube-dns:dns-tcp info from k8s - configured in upstreams
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    service_id: 1
services:
  -
    id: 1
    upstream_id : 1
upstreams:
  -
    id: 1
    service_name : kube-system/kube-dns:dns-tcp
    type: roundrobin
    discovery_type: k8s
    timeout:
      connect: 0.5
      send : 1
      read : 1
#END
--- request
GET /hello
--- error_code: 504
