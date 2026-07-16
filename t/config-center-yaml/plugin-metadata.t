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

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
plugin_metadata:
  - id: http-logger
    log_format:
        host: "$host"
        remote_addr: "$remote_addr"
#END
--- request
GET /hello
--- error_log
"remote_addr":"127.0.0.1"



=== TEST 2: sanity
--- apisix_yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
plugin_metadata:
  - id: authz-casbin
    model: 123
#END
--- request
GET /hello
--- error_log
failed to check item data of [plugin_metadata]



=== TEST 3: metadata of plugins from the other subsystem should be skipped silently
--- yaml_config
apisix:
    node_listen: 1984
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - 9100
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- stream_enable
--- apisix_yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
    plugins:
        cors:
            allow_origins_by_metadata:
                - local
plugin_metadata:
  - id: cors
    allow_origins:
        local: "http://example.com"
  - id: mqtt-proxy
    log_format:
        host: "$host"
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
disabled or unknown plugin



=== TEST 4: metadata of a disabled or unknown plugin is ignored silently
--- extra_yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- apisix_yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
plugin_metadata:
  - id: plugin-not-exist
    log_format:
        host: "$host"
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
disabled or unknown plugin
failed to check item data of [plugin_metadata]
failed to get schema



=== TEST 5: metadata entry without id is ignored silently
--- apisix_yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
plugin_metadata:
  - log_format:
        host: "$host"
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
disabled or unknown plugin
failed to check item data of [plugin_metadata]
