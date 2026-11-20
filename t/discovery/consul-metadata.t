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
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $::yaml_config);
    }

    if (!$block->request && !$block->pipelined_requests) {
        $block->set_value("request", "GET /hello");
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
  consul:
    servers:
      - "http://127.0.0.1:8500"
    preserve_metadata: true
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
_EOC_

our $yaml_config_no_metadata = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
_EOC_


run_tests();

__DATA__

=== TEST 1: register nodes of service_lane with different metadata
--- yaml_config eval: $::yaml_config_no_metadata
--- config
location /consul1 {
    rewrite  ^/consul1/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:8500;
}
--- pipelined_requests eval
[
    "PUT /consul1/deregister/service_lane_a",
    "PUT /consul1/deregister/service_lane_b",
    "PUT /consul1/register\n" . "{\"ID\":\"service_lane_a\",\"Name\":\"service_lane\",\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"lane\":\"a\",\"env\":\"prod\"}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_lane_b\",\"Name\":\"service_lane\",\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"lane\":\"b\",\"env\":\"prod\"}}",
]
--- error_code eval
[200, 200, 200, 200]



=== TEST 2: only use the nodes matching discovery_args.metadata
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_lane
      discovery_type: consul
      type: roundrobin
      discovery_args:
        metadata:
          lane: b
          env: prod
#END
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello",
    "GET /hello",
]
--- response_body eval
[
    "server 2\n",
    "server 2\n",
    "server 2\n",
]
--- no_error_log
[error]



=== TEST 3: no node matches discovery_args.metadata
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_lane
      discovery_type: consul
      type: roundrobin
      discovery_args:
        metadata:
          lane: c
#END
--- error_code: 503
--- error_log
no valid upstream node



=== TEST 4: without discovery_args.metadata all nodes are used
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_lane
      discovery_type: consul
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
[error]



=== TEST 5: the nodes given to the upstream do not carry the consul metadata
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(1.5)
        local consul = require("apisix.discovery.consul")
        local nodes = consul.nodes("service_lane", {metadata = {lane = "a"}})
        ngx.say(#nodes, " ", nodes[1].port, " ", tostring(nodes[1].metadata))

        nodes = consul.nodes("service_lane")
        ngx.say(#nodes, " ", tostring(nodes[1].metadata), " ",
                tostring(nodes[2].metadata))
    }
}
--- request
GET /t
--- response_body
1 30511 nil
2 nil nil



=== TEST 6: discovery_args.metadata is ignored when preserve_metadata is off
--- yaml_config eval: $::yaml_config_no_metadata
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_lane
      discovery_type: consul
      type: roundrobin
      discovery_args:
        metadata:
          lane: b
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
--- error_log
discovery_args.metadata of service service_lane is ignored



=== TEST 7: check discovery_args.metadata against the consul configuration
--- yaml_config eval: $::yaml_config_no_metadata
--- config
location /t {
    content_by_lua_block {
        local consul = require("apisix.discovery.consul")
        local args = {metadata = {lane = "b"}}

        ngx.say(consul.check_discovery_args(nil, "service_lane", false))
        ngx.say(consul.check_discovery_args(args, "service_lane", true))

        local ok, err = consul.check_discovery_args(args, "service_lane", false)
        ngx.say(ok, " ", err)
    }
}
--- request
GET /t
--- response_body
true
true
false discovery_args.metadata requires discovery.consul.preserve_metadata to be true



=== TEST 8: discovery_args.metadata values must be strings
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local ok, err = core.schema.check(core.schema.upstream, {
            service_name = "service_lane",
            discovery_type = "consul",
            type = "roundrobin",
            discovery_args = {
                metadata = {lane = 1},
            },
        })
        ngx.say(ok, " ", err ~= nil and err:find("metadata", 1, true) ~= nil)

        ok = core.schema.check(core.schema.upstream, {
            service_name = "service_lane",
            discovery_type = "consul",
            type = "roundrobin",
            discovery_args = {
                metadata = {lane = "b"},
            },
        })
        ngx.say(ok)
    }
}
--- request
GET /t
--- response_body
false true
true
