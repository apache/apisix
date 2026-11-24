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
use Cwd qw(abs_path);
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

my $certs = abs_path("t/certs");
our $tls_servers = <<_EOC_;
    server {
        listen 21981 ssl;
        listen 21983;
        ssl_certificate $certs/localhost_slapd_cert.pem;
        ssl_certificate_key $certs/localhost_slapd_key.pem;
        location / {
            content_by_lua_block { ngx.log(ngx.WARN, "collector received ", ngx.var.uri) }
        }
    }
    server {
        listen 21982 ssl;
        ssl_certificate cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;
        location / { return 200; }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: accept the trusted receiver identity
--- http_config eval: $::tls_servers
--- apisix_yaml
routes:
  - uri: /send
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1
    plugins:
      proxy-rewrite:
        uri: /hello
      skywalking-logger:
        batch_max_size: 1
        endpoint_addr: "https://localhost:21981"
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
collector received /v3/logs



=== TEST 2: reject a certificate for another host
--- http_config eval: $::tls_servers
--- apisix_yaml
routes:
  - uri: /send
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1
    plugins:
      proxy-rewrite:
        uri: /hello
      skywalking-logger:
        batch_max_size: 1
        endpoint_addr: "https://localhost:21982"
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
certificate host mismatch



=== TEST 3: skip certificate verification when ssl_verify is false
--- http_config eval: $::tls_servers
--- apisix_yaml
routes:
  - uri: /send
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1
    plugins:
      proxy-rewrite:
        uri: /hello
      skywalking-logger:
        batch_max_size: 1
        endpoint_addr: "https://127.0.0.1:21981"
        ssl_verify: false
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
collector received /v3/logs
Keeping ssl_verify disabled in skywalking-logger configuration is a security risk
--- no_error_log
certificate host mismatch



=== TEST 4: ssl_verify does not affect an http endpoint
--- http_config eval: $::tls_servers
--- apisix_yaml
routes:
  - uri: /send
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1
    plugins:
      proxy-rewrite:
        uri: /hello
      skywalking-logger:
        batch_max_size: 1
        endpoint_addr: "http://127.0.0.1:21983"
        ssl_verify: true
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
collector received /v3/logs
