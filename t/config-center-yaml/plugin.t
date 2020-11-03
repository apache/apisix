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
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    my $routes = <<_EOC_;
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $routes);

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
plugins:
  - name: ip-restriction
  - name: jwt-auth
  - name: mqtt-proxy
    stream: true
--- request
GET /hello
--- response_body
hello world
--- error_log
use config_center: yaml
load(): new plugins: {"ip-restriction":true,"jwt-auth":true}
load_stream(): new plugins: {"mqtt-proxy":true}
--- grep_error_log eval
qr/load\(\): new plugins/
--- grep_error_log_out
load(): new plugins
load(): new plugins



=== TEST 2: plugins not changed
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
plugins:
    - ip-restriction
    - jwt-auth
stream_plugins:
    - mqtt-proxy
--- apisix_yaml
plugins:
  - name: ip-restriction
  - name: jwt-auth
  - name: mqtt-proxy
    stream: true
--- request
GET /hello
--- response_body
hello world
--- error_log
load(): new plugins: {"ip-restriction":true,"jwt-auth":true}
load_stream(): new plugins: {"mqtt-proxy":true}
load(): plugins not changed
load_stream(): plugins not changed



=== TEST 3: disable plugin and its router
--- apisix_yaml
plugins:
  - name: jwt-auth
--- request
GET /apisix/prometheus/metrics
--- error_code: 404



=== TEST 4: enable plugin and its router
--- apisix_yaml
plugins:
  - name: prometheus
--- request
GET /apisix/prometheus/metrics



=== TEST 5: invalid plugin config
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
plugins:
    - ip-restriction
    - jwt-auth
stream_plugins:
    - mqtt-proxy
--- apisix_yaml
plugins:
  - name: xxx
    stream: ip-restriction
--- request
GET /hello
--- response_body
hello world
--- error_log
property "stream" validation failed: wrong type: expected boolean, got string
--- no_error_log
load(): plugins not changed
