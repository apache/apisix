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
_EOC_

run_tests();

__DATA__

=== TEST 1: get APISIX-EUREKA info from EUREKA
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /eureka/*
    upstream:
      service_name: APISIX-EUREKA
      discovery_type: eureka
      type: roundrobin

#END
--- request
GET /eureka/apps/APISIX-EUREKA
--- response_body_like
.*<name>APISIX-EUREKA</name>.*
--- error_log
use config_center: yaml
default_weight:80.
fetch_interval:10.
eureka uri:http://127.0.0.1:8761/eureka/.
connect_timeout:1500, send_timeout:1500, read_timeout:1500.
--- no_error_log
[error]



=== TEST 2: error service_name name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /eureka/*
    upstream:
      service_name: APISIX-EUREKA-DEMO
      discovery_type: eureka
      type: roundrobin

#END
--- request
GET /eureka/apps/APISIX-EUREKA
--- error_code: 503
--- error_log eval
qr/.* no valid upstream node.*/



=== TEST 3: with proxy-rewrite
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /eureka-test/*
    plugins:
      proxy-rewrite:
        regex_uri: ["^/eureka-test/(.*)", "/${1}"]
    upstream:
      service_name: APISIX-EUREKA
      discovery_type: eureka
      type: roundrobin

#END
--- request
GET /eureka-test/eureka/apps/APISIX-EUREKA
--- response_body_like
.*<name>APISIX-EUREKA</name>.*
--- error_log
use config_center: yaml
default_weight:80.
fetch_interval:10.
eureka uri:http://127.0.0.1:8761/eureka/.
connect_timeout:1500, send_timeout:1500, read_timeout:1500.
--- no_error_log
[error]
