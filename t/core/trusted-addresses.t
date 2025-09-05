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

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: without trusted_addresses configuration, X-Forwarded headers should be overridden
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 2: with IP, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "127.0.0.1"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 3: with multiple IPs, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "127.0.0.1"
        - "127.0.0.2"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 4: with CIDR, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "127.0.0.0/24"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 5: with multiple CIDRs, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "127.0.0.0/24"
        - "1.1.1.0/24"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 6: with multiple IPs and CIDRs, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "127.0.0.0/24"
        - "1.1.1.0/24"
        - "127.0.0.1"
        - "1.1.1.1"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 7: with `0.0.0.0/0`, X-Forwarded headers should be preserved from trusted client
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "0.0.0.0/0"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1



=== TEST 8: with trusted_addresses configuration, but client not in trusted list, X-Forwarded headers should be overridden
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "1.0.0.1"
        - "10.0.0.0/8"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 9: invalid trusted_addresses configuration: IP is invalid
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "1.0.0"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_log
invalid IP/CIDR '1.0.0' exists in trusted_addresses



=== TEST 10: invalid trusted_addresses configuration: CIDR is invalid
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "1.0.0.0/33"
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /old_uri
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_log
invalid IP/CIDR '1.0.0.0/33' exists in trusted_addresses
