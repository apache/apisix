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

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
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

=== TEST 1: get APISIX-NACOS info from NACOS - no auth
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
--- config
location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- timeout: 15
--- pipelined_requests eval
[
    "GET /sleep?sec=10",
    "GET /hello",
    "GET /hello",
]
--- response_body_like eval
[
    qr/ok\n/,
    qr/server [1-2]/,
    qr/server [1-2]/,
]
--- no_error_log
[error, error, error]



=== TEST 2: error service_name name - no auth
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



=== TEST 3: get APISIX-NACOS info from NACOS - auth
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
    qr/server [1-2]/,
    qr/server [1-2]/,
]
--- no_error_log
[error, error]



=== TEST 4: error service_name name - auth
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
