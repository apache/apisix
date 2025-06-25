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
    - id: "svc1"
      hosts:
      - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      default_weight: 1
      timeout:
        connect: 2000
        send: 2000
        read: 5000
    - id: "svc2"
      hosts:
      - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      default_weight: 1
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
    - id: "svc1"
      hosts:
      - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      default_weight: 1
      auth:
        username: nacos
        password: nacos
      timeout:
        connect: 2000
        send: 2000
        read: 5000
    - id: "svc2"
      hosts:
      - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      default_weight: 1
      auth:
        username: nacos
        password: nacos
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
      service_name: svc1/public/DEFAULT_GROUP/APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        id: svc1
  -
    uri: /hello2
    upstream:
      service_name: svc2/public/DEFAULT_GROUP/APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        id: svc2
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
--- timeout: 10
