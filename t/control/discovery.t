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


our $yaml_config = <<_EOC_;
apisix:
  enable_control: true
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  eureka:
    host:
      - "http://127.0.0.1:8761"
    prefix: "/eureka/"
    fetch_interval: 10
    weight: 80
    timeout:
      connect: 1500
      send: 1500
      read: 1500
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
  dns:
    servers:
      - "127.0.0.1:1053"
_EOC_


run_tests();

__DATA__

=== TEST 1: test consul_kv dump_data api
--- yaml_config eval: $::yaml_config
--- request
GET /v1/discovery/consul_kv/dump
--- error_code: 200
--- response_body_unlike
^{}$



=== TEST 2: test eureka dump_data api
--- yaml_config eval: $::yaml_config
--- request
GET /v1/discovery/eureka/dump
--- error_code: 200
--- response_body_unlike
^{}$



=== TEST 3: test dns api
--- yaml_config eval: $::yaml_config
--- request
GET /v1/discovery/dns/dump
--- error_code: 404



=== TEST 4: test unconfiged consul_kv dump_data api
--- yaml_config
apisix:
  enable_control: true
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
#END
--- request
GET /v1/discovery/eureka/dump
--- error_code: 404
