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
no_shuffle();
no_root_location();

our $receiver = <<'_EOC_';
    server {
        listen 21981 ssl;
        listen 21982;
        ssl_certificate cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;
        content_by_lua_block {
            local sock = assert(ngx.req.socket())
            local data = sock:receive(1)
            if data then ngx.log(ngx.WARN, "received log data") end
        }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: accept the trusted receiver identity
--- stream_config eval: $::receiver
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
      tcp-logger:
        batch_max_size: 1
        host: "127.0.0.1"
        port: 21981
        tls: true
        tls_options: "test.com"
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
received log data



=== TEST 2: reject a certificate for another host
--- stream_config eval: $::receiver
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
      tcp-logger:
        batch_max_size: 1
        host: "127.0.0.1"
        port: 21981
        tls: true
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
certificate host mismatch



=== TEST 3: error-log-logger accepts the configured server identity
--- stream_config eval: $::receiver
--- http_config
    lua_ssl_trusted_certificate cert/apisix.crt;
--- apisix_yaml
plugin_metadata:
  - id: error-log-logger
    level: CRIT
    batch_max_size: 1
    tcp:
      host: "127.0.0.1"
      port: 21981
      tls: true
      tls_server_name: "test.com"
#END
--- extra_yaml_config
plugins:
  - error-log-logger
--- config
    location = /trigger {
        content_by_lua_block { ngx.log(ngx.CRIT, "test log entry") }
    }
--- request
GET /trigger
--- wait: 3
--- error_log
received log data



=== TEST 4: error-log-logger rejects a mismatched server identity
--- stream_config eval: $::receiver
--- http_config
    lua_ssl_trusted_certificate cert/apisix.crt;
--- apisix_yaml
plugin_metadata:
  - id: error-log-logger
    level: CRIT
    batch_max_size: 1
    tcp:
      host: "127.0.0.1"
      port: 21981
      tls: true
#END
--- extra_yaml_config
plugins:
  - error-log-logger
--- config
    location = /trigger {
        content_by_lua_block { ngx.log(ngx.CRIT, "test log entry") }
    }
--- request
GET /trigger
--- wait: 3
--- error_log
certificate host mismatch



=== TEST 5: tcp-logger skips certificate verification when tls_verify is false
--- stream_config eval: $::receiver
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
      tcp-logger:
        batch_max_size: 1
        host: "127.0.0.1"
        port: 21981
        tls: true
        tls_verify: false
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
received log data
--- no_error_log
certificate host mismatch



=== TEST 6: tcp-logger tls_verify does not affect plain TCP
--- stream_config eval: $::receiver
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
      tcp-logger:
        batch_max_size: 1
        host: "127.0.0.1"
        port: 21982
        tls_verify: true
#END
--- request
GET /send
--- response_body
hello world
--- wait: 0.5
--- error_log
received log data



=== TEST 7: error-log-logger skips certificate verification when tls_verify is false
--- stream_config eval: $::receiver
--- http_config
    lua_ssl_trusted_certificate cert/apisix.crt;
--- apisix_yaml
plugin_metadata:
  - id: error-log-logger
    level: CRIT
    batch_max_size: 1
    tcp:
      host: "127.0.0.1"
      port: 21981
      tls: true
      tls_verify: false
#END
--- extra_yaml_config
plugins:
  - error-log-logger
--- config
    location = /trigger {
        content_by_lua_block { ngx.log(ngx.CRIT, "test log entry") }
    }
--- request
GET /trigger
--- wait: 3
--- error_log
received log data
--- no_error_log
certificate host mismatch
