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

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 9080
  config_center: yaml
  enable_admin: false
discovery:
  nacos:
    host:
      - "http://127.0.0.1:8848"
    username: nacos
    password: nacos
    prefix: "/nacos/v1/"
    fetch_interval: 30
    weight: 100
    timeout:
      connect: 2000
      send: 2000
      read: 5000
_EOC_

run_tests();

__DATA__

=== TEST 1: get APISIX-Nacos info from Nacos
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /ping
    upstream:
      service_name: dev:DEFAULT_GROUP:ping_demo
      discovery_type: nacos
      type: roundrobin
#END
--- request
GET /ping
--- response_body
pong from Nacos
--- no_error_log
[error]

=== TEST 2: get APISIX-Nacos info from Nacos with default groupName: DEFAULT_GROUP
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /ping
    upstream:
      service_name: dev:ping_demo
      discovery_type: nacos
      type: roundrobin
#END
--- request
GET /ping
--- response_body
pong from Nacos
--- no_error_log
[error]

=== TEST 3: error service_name with default namespaceId: public
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /ping
    upstream:
      service_name: ping_demo
      discovery_type: nacos
      type: roundrobin
#END
--- request
GET /ping
--- error_code: 503

=== TEST 4: with proxy-rewrite
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /nacos-test/*
    plugins:
      proxy-rewrite:
        regex_uri: ["^/nacos-test/(.*)", "/${1}"]
    upstream:
      service_name: dev:DEFAULT_GROUP:ping_demo
      discovery_type: nacos
      type: roundrobin
#END
--- request
GET /nacos-test/ping
--- response_body_like
pong from Nacos.*
--- no_error_log
[error]
