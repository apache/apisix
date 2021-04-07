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
        listen 18001;

        location /hello {
            content_by_lua_block {
                ngx.say("server 1")
            }
        }
    }
    server {
        listen 18002;

        location /hello {
            content_by_lua_block {
                ngx.say("server 2")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      prefix: "/nacos/v1/"
      fetch_interval: 30
      weight: 100
      timeout:
        connect: 2000
        send: 2000
        read: 5000

_EOC_

our $yaml_auth_config = <<_EOC_;
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  nacos:
      host:
        - "http://nacos:nacos\@127.0.0.1:8848"
      prefix: "/nacos/v1/"
      fetch_interval: 30
      weight: 100
      timeout:
        connect: 2000
        send: 2000
        read: 5000

_EOC_

run_tests();

__DATA__

=== TEST 1: prepare nacos register nodes
--- config
location /nacos {
    proxy_pass http://127.0.0.1:8858;
}

--- pipelined_requests eval
[
    "POST /nacos/v1/ns/instance?port=18001&healthy=true&ip=127.0.0.1&weight=1.0&serviceName=APISIX-NACOS&encoding=GBK&enabled=true&clusterName=c1",
    "POST /nacos/v1/ns/instance?port=18002&healthy=true&ip=127.0.0.1&weight=1.0&serviceName=APISIX-NACOS&encoding=GBK&enabled=true&clusterName=c1",
]
--- response_code eval
[200, 200]
--- wait: 2



=== TEST 2: get APISIX-NACOS info from NACOS - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello",
]
--- response_body_like eval
[
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
]
--- no_error_log
[error, error]



=== TEST 3: error service_name name - no auth
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin

#END
--- request
GET /hello
--- error_code: 503



=== TEST 4: get APISIX-NACOS info from NACOS - auth
--- yaml_config eval: $::yaml_auth_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello",
]
--- response_body_like eval
[
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
]
--- no_error_log
[error, error]



=== TEST 5: error service_name name - auth
--- yaml_config eval: $::yaml_auth_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS-DEMO
      discovery_type: nacos
      type: roundrobin

#END
--- request
GET /hello
--- error_code: 503
