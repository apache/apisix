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
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8848"
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

=== TEST 1: get APISIX-NACOS info from NACOS
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /echo/*
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
--- request
GET /echo/APISIX-NACOS
--- response_body_like
.*APISIX-NACOS.*


=== TEST 2: error service_name name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /echo/*
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin

#END
--- request
GET /echo/APISIX-NACOS
--- error_code: 503
--- error_log eval
qr/.* no valid upstream node.*/








