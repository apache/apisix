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


add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 20999;

        location / {
            content_by_lua_block {
                ngx.say("missing consul_kv services")
            }
        }
    }

    server {
        listen 30511;

        location /hello {
            content_by_lua_block {
                ngx.say("server 1")
            }
        }
    }
    server {
        listen 30512;

        location /hello {
            content_by_lua_block {
                ngx.say("server 2")
            }
        }
    }
    server {
        listen 30513;

        location /hello {
            content_by_lua_block {
                ngx.say("server 3")
            }
        }
    }
    server {
        listen 30514;

        location /hello {
            content_by_lua_block {
                ngx.say("server 4")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->stream_request) {
        $block->set_value("stream_request", "GET /hello HTTP/1.1\r\nHost: 127.0.0.1:1985\r\nConnection: close\r\n\r\n");
    }
});

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_keys:
      - "upstreams/unused_api/"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
    default_service:
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1
        weight: 1
        max_fails: 1
_EOC_


run_tests();

__DATA__

=== TEST 1: prepare consul kv register nodes
--- config
location /consul1 {
    rewrite  ^/consul1/(.*) /v1/kv/$1 break;
    proxy_pass http://127.0.0.1:8500;
}

location /consul2 {
    rewrite  ^/consul2/(.*) /v1/kv/$1 break;
    proxy_pass http://127.0.0.1:8600;
}
--- pipelined_requests eval
[
    "DELETE /consul1/upstreams/webpages/?recurse=true",
    "DELETE /consul2/upstreams/webpages/?recurse=true",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30512\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30513\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30514\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
]
--- response_body eval
["true", "true", "true", "true", "true", "true"]



=== TEST 2: test consul server 1
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- stream_response eval
qr/server [1-2]/
--- no_error_log
[error]



=== TEST 3: test consul server 2
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- stream_response eval
qr/server [3-4]/
--- no_error_log
[error]



=== TEST 4: test mini consul_kv config
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:6500"
#END
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- stream_response eval
qr/server [1-2]/
--- ignore_error_log



=== TEST 5: test invalid service name
sometimes the consul key maybe deleted by mistake
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/deleted_keys/
      discovery_type: consul_kv
      type: roundrobin
#END
--- stream_response_like
missing consul_kv services
--- ignore_error_log



=== TEST 6: test skip keys
skip some keys, return default nodes, get response: missing consul_kv services
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_keys:
      - "upstreams/webpages/"
    default_service:
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1
        weight: 1
        max_fails: 1
#END
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- stream_response_like
missing consul_kv services
--- ignore_error_log
