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
workers(1);

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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->stream_request) {
        # GET /hello HTTP/1.1\r\nHost: 127.0.0.1:1985\r\nConnection: close\r\n\r\n
        $block->set_value("stream_request", "\x47\x45\x54\x20\x2f\x68\x65\x6c\x6c\x6f\x20\x48\x54\x54\x50\x2f\x31\x2e\x31\x0d\x0a\x48\x6f\x73\x74\x3a\x20\x31\x32\x37\x2e\x30\x2e\x30\x2e\x31\x3a\x31\x39\x38\x35\x0d\x0a\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x3a\x20\x63\x6c\x6f\x73\x65\x0d\x0a\x0d\x0a");
    }

});

run_tests();

__DATA__

=== TEST 1: get APISIX-NACOS info from NACOS - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
--- stream_response eval
qr/server [1-2]/
--- no_error_log
[error]



=== TEST 2: error service_name name - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin
#END
--- error_log
no valid upstream node
