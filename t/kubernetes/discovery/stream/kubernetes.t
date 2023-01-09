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

BEGIN {
    our $token_file = "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token";
    our $token_value = eval {`cat $token_file 2>/dev/null`};

    our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    - id: first
      service:
        host: "127.0.0.1"
        port: "6443"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
    - id: second
      service:
        schema: "http",
        host: "127.0.0.1",
        port: "6445"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"

_EOC_

}

use t::APISIX 'no_plan';

repeat_each(1);
log_level('warn');
no_root_location();
no_shuffle();
workers(4);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $apisix_yaml = $block->apisix_yaml // <<_EOC_;
routes: []
#END
_EOC_

    if (!$block->apisix_yaml) {
      $block->set_value("apisix_yaml", $apisix_yaml);
    }

    my $main_config = $block->main_config // <<_EOC_;
env KUBERNETES_SERVICE_HOST=127.0.0.1;
env KUBERNETES_SERVICE_PORT=6443;
env KUBERNETES_CLIENT_TOKEN=$::token_value;
env KUBERNETES_CLIENT_TOKEN_FILE=$::token_file;
_EOC_

    $block->set_value("main_config", $main_config);

});

run_tests();

__DATA__

=== TEST 1: connect to first/default/kubernetes:https endpoints
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream:
      service_name: first/default/kubernetes:https
      discovery_type: kubernetes
      type: roundrobin

#END
--- stream_request
"GET /hello HTTP/1.1\r\nHost: 127.0.0.1:1985\r\nConnection: close\r\n\r\n"
--- log_level: info
--- error_log eval
qr/proxy request to \S+:6443/



=== TEST 2: connect to first/ns-d/ep:p1 endpoints, no valid upstreams node
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream:
      service_name: first/ns-d/ep:p1
      discovery_type: kubernetes
      type: roundrobin

#END
--- stream_request
"GET /hello HTTP/1.1\r\nHost: 127.0.0.1:1985\r\nConnection: close\r\n\r\n"
--- error_log
no valid upstream node
