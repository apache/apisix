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



=== TEST 11: without trusted_addresses, a request carrying no X-Forwarded-* header keeps the nginx-derived values
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
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 12: with trusted_addresses, an untrusted peer carrying no X-Forwarded-* header gets the same values
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    trusted_addresses:
        - "1.0.0.1"
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
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 13: without trusted_addresses, RFC 7239 Forwarded alone is cleared and X-Forwarded-* are overridden
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
Forwarded: for=1.2.3.4;host=evil.com;proto=https
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 14: without trusted_addresses, a forged X-Forwarded-For alone still overrides the other X-Forwarded-*
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
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 1.2.3.4, 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 15: without trusted_addresses and without any X-Forwarded-* header, an explicit port in Host is preserved
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
Host: localhost:8443
--- response_body
uri: /old_uri
host: localhost:8443
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost:8443
x-forwarded-port: 8443
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 16: without trusted_addresses and without any X-Forwarded-* header, the Host header case is preserved
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
Host: LOCALHOST
--- response_body
uri: /old_uri
host: LOCALHOST
x-forwarded-for: 127.0.0.1
x-forwarded-host: LOCALHOST
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 17: a request carrying no X-Forwarded-* still gets them in r->headers_in
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
    plugins:
        serverless-pre-function:
            phase: rewrite
            functions:
              - return function(conf, ctx) local h = ngx.req.get_headers(); ngx.log(ngx.WARN, "header-table xfp=", tostring(h["x-forwarded-proto"]), " xfh=", tostring(h["x-forwarded-host"]), " xfport=", tostring(h["x-forwarded-port"])) end
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_log
header-table xfp=http xfh=localhost xfport=1984



=== TEST 18: a route matching on http_x_forwarded_proto still matches without one
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
    vars:
      - ["http_x_forwarded_proto", "==", "http"]
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_code: 200
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 17: a request carrying no X-Forwarded-* still gets them in r->headers_in
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
    plugins:
        serverless-pre-function:
            phase: rewrite
            functions:
              - return function(conf, ctx) local h = ngx.req.get_headers(); ngx.log(ngx.WARN, "header-table xfp=", tostring(h["x-forwarded-proto"]), " xfh=", tostring(h["x-forwarded-host"]), " xfport=", tostring(h["x-forwarded-port"])) end
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_log
header-table xfp=http xfh=localhost xfport=1984



=== TEST 18: a route matching on http_x_forwarded_proto still matches without one
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
    vars:
      - ["http_x_forwarded_proto", "==", "http"]
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- error_code: 200
--- response_body
uri: /old_uri
host: localhost
x-forwarded-for: 127.0.0.1
x-forwarded-host: localhost
x-forwarded-port: 1984
x-forwarded-proto: http
x-real-ip: 127.0.0.1



=== TEST 19: the injected headers are single-valued, including through an ngx.exec target
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
    plugins:
        proxy-buffering:
            disable_proxy_buffering: true
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /old_uri
--- response_body_like eval
qr/\nx-forwarded-host: localhost\nx-forwarded-port: 1984\nx-forwarded-proto: http\n/
