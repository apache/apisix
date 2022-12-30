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
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
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
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream:
      service_name: APISIX-EUREKA
      discovery_type: eureka
      type: roundrobin

#END
--- stream_request eval
"\x47\x45\x54\x20\x2f\x65\x75\x72\x65\x6b\x61\x2f\x61\x70\x70\x73\x2f\x41\x50\x49\x53\x49\x58\x2d\x45\x55\x52\x45\x4b\x41\x20\x48\x54\x54\x50\x2f\x31\x2e\x31\x0d\x0a\x48\x6f\x73\x74\x3a\x20\x31\x32\x37\x2e\x30\x2e\x30\x2e\x31\x3a\x31\x39\x38\x35\x0d\x0a\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x3a\x20\x63\x6c\x6f\x73\x65\x0d\x0a\x0d\x0a"
--- stream_response_like
.*<name>APISIX-EUREKA</name>.*
--- error_log
use config_provider: yaml
default_weight:80.
fetch_interval:10.
eureka uri:http://127.0.0.1:8761/eureka/.
connect_timeout:1500, send_timeout:1500, read_timeout:1500.



=== TEST 2: error service_name name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream:
      service_name: APISIX-EUREKA-DEMO
      discovery_type: eureka
      type: roundrobin

#END
--- stream_request eval
"\x47\x45\x54\x20\x2f\x65\x75\x72\x65\x6b\x61\x2f\x61\x70\x70\x73\x2f\x41\x50\x49\x53\x49\x58\x2d\x45\x55\x52\x45\x4b\x41\x20\x48\x54\x54\x50\x2f\x31\x2e\x31\x0d\x0a\x48\x6f\x73\x74\x3a\x20\x31\x32\x37\x2e\x30\x2e\x30\x2e\x31\x3a\x31\x39\x38\x35\x0d\x0a\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x3a\x20\x63\x6c\x6f\x73\x65\x0d\x0a\x0d\x0a"
--- error_log eval
qr/.* no valid upstream node.*/
