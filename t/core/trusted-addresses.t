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

=== TEST 1: without trusted_addresses, X-Forwarded-For is preserved while others are overridden
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
X-Forwarded-For: 1.2.3.4
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 1.2.3.4, 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- error_log
trusted_addresses is not configured
--- no_error_log
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
X-Forwarded-For: 1.2.3.4
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 1.2.3.4, 127.0.0.1
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



=== TEST 8: client not in trusted list, X-Forwarded-For is reset along with the others
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
X-Forwarded-For: 1.2.3.4
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



=== TEST 9: client not in trusted list, RFC 7239 Forwarded header is cleared
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
Forwarded: for=1.2.3.4;host=evil.com;proto=https
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 10: with `0.0.0.0/0`, RFC 7239 Forwarded header is preserved from trusted client
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
Forwarded: for=1.2.3.4;host=evil.com;proto=https
X-Forwarded-Proto: https
X-Forwarded-Host: example.com
X-Forwarded-Port: 8443
--- response_body
uri: /old_uri
forwarded: for=1.2.3.4;host=evil.com;proto=https
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com
x-forwarded-port: 8443
x-forwarded-proto: https
x-real-ip: 127.0.0.1



=== TEST 11: Host carrying a port sets X-Forwarded-Host and X-Forwarded-Port from it
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
Host: example.com:8443
--- response_body
uri: /old_uri
host: example.com:8443
x-forwarded-for: 127.0.0.1
x-forwarded-host: example.com:8443
x-forwarded-port: 8443
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- error_log
trusted_addresses is not configured
--- no_error_log
trusted_addresses_matcher is not initialized



=== TEST 12: request without a Host header falls back to $host
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
        pass_host: rewrite
        upstream_host: localhost
#END
--- raw_request eval
"GET /old_uri HTTP/1.0\r\n\r\n"
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
--- no_error_log
trusted_addresses_matcher is not initialized



=== TEST 13: trusted client that sent no X-Forwarded-* gets the observed values
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
Host: Example.COM:8443
--- response_body
uri: /old_uri
host: Example.COM:8443
x-forwarded-for: 127.0.0.1
x-forwarded-host: Example.COM:8443
x-forwarded-port: 8443
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 14: trusted client, proxy-rewrite of X-Forwarded-Proto reaches the upstream
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
    plugins:
        proxy-rewrite:
            headers:
                X-Forwarded-Proto: https
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-Proto: grpc
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: https
x-real-ip: 127.0.0.1
--- no_error_log
trusted_addresses is not configured
trusted_addresses_matcher is not initialized



=== TEST 15: client not in trusted list, every forged forwarding header is dropped
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
X-Forwarded-For: 9.9.9.9
X-Forwarded-Proto: https
X-Forwarded-Host: evil.com
Forwarded: for=1.2.3.4
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



=== TEST 16: trusted client sending an empty X-Forwarded-Proto gets the observed one
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
X-Forwarded-Proto:
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 17: the client's original X-Forwarded-For stays readable after it is cleared
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
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
    plugins:
        serverless-pre-function:
            phase: access
            functions:
              - "return function(conf, ctx) ngx.log(ngx.WARN, \"orig xff: \", tostring(ctx.var.apisix_orig_xf_for)) end"
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- more_headers
X-Forwarded-For: 9.9.9.9, 8.8.8.8
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1
--- error_log
orig xff: 9.9.9.9, 8.8.8.8

