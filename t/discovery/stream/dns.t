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
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1:1053"
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
stream_routes:
  - id: 1
    server_port: 1985
    upstream_id: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->stream_request) {
        $block->set_value("stream_request", "GET /hello HTTP/1.0\r\nHost: 127.0.0.1:1985\r\n\r\n");
    }

});

run_tests();

__DATA__

=== TEST 1: default port to 53
--- log_level: debug
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1"
--- apisix_yaml
upstreams:
    - service_name: sd.test.local
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
connect to 127.0.0.1:53



=== TEST 2: A
--- apisix_yaml
upstreams:
    - service_name: "sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":1,"127.0.0.2:1980":1|"127.0.0.2:1980":1,"127.0.0.1:1980":1)\}/
--- stream_response_like
hello world



=== TEST 3: AAAA
--- listen_ipv6
--- apisix_yaml
upstreams:
    - service_name: "ipv6.sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- stream_response_like
hello world
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to [0:0:0:0:0:0:0:1]:1980



=== TEST 4: prefer A to AAAA
--- listen_ipv6
--- apisix_yaml
upstreams:
    - service_name: "mix.sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- stream_response_like
hello world
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1980



=== TEST 5: no /etc/hosts
--- apisix_yaml
upstreams:
    - service_name: test.com
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
failed to query the DNS server



=== TEST 6: no /etc/resolv.conf
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    enable_resolv_search_option: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1:1053"
--- apisix_yaml
upstreams:
    - service_name: apisix
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
failed to query the DNS server



=== TEST 7: SRV
--- apisix_yaml
upstreams:
    - service_name: "srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":20|"127.0.0.2:1980":20,"127.0.0.1:1980":60)\}/
--- stream_response_like
hello world



=== TEST 8: SRV (RFC 2782 style)
--- apisix_yaml
upstreams:
    - service_name: "_sip._tcp.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":20|"127.0.0.2:1980":20,"127.0.0.1:1980":60)\}/
--- stream_response_like
hello world



=== TEST 9: SRV (different port)
--- apisix_yaml
upstreams:
    - service_name: "port.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1981":20|"127.0.0.2:1981":20,"127.0.0.1:1980":60)\}/
--- stream_response_like
hello world



=== TEST 10: SRV (zero weight)
--- apisix_yaml
upstreams:
    - service_name: "zero-weight.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":1|"127.0.0.2:1980":1,"127.0.0.1:1980":60)\}/
--- stream_response_like
hello world



=== TEST 11: SRV (split weight)
--- apisix_yaml
upstreams:
    - service_name: "split-weight.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{(,?"127.0.0.(1:1980":200|3:1980":1|4:1980":1)){3}\}/
--- stream_response_like
hello world



=== TEST 12: SRV (priority)
--- apisix_yaml
upstreams:
    - service_name: "priority.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- stream_response_like
hello world
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1980



=== TEST 13: prefer SRV than A
--- apisix_yaml
upstreams:
    - service_name: "srv-a.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
proxy request to 127.0.0.1:1980
--- stream_response_like
hello world



=== TEST 14: SRV (port is 0)
--- apisix_yaml
upstreams:
    - service_name: "zero.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
no valid upstream node



=== TEST 15: SRV (override port)
--- apisix_yaml
upstreams:
    - service_name: "port.srv.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":20|"127.0.0.2:1980":20,"127.0.0.1:1980":60)\}/
--- stream_response_like
hello world



=== TEST 16: prefer A than SRV when A is ahead of SRV in config.yaml
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:
    dns:
        servers:
            - "127.0.0.1:1053"
        order:
            - A
            - SRV
--- apisix_yaml
upstreams:
    - service_name: "srv-a.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
no valid upstream node
