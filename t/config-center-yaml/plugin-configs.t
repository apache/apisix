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

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
plugin_configs:
    -
        id: 1
        plugins:
            response-rewrite:
                body: "hello\n"
routes:
    - id: 1
      uri: /hello
      plugin_config_id: 1
      upstream:
        nodes:
          "127.0.0.1:1980":1
        type: roundrobin
#END
--- response_body
hello



=== TEST 2: plugin_config not found
--- apisix_yaml
routes:
    - id: 1
      uri: /hello
      plugin_config_id: 1
      upstream:
        nodes:
          "127.0.0.1:1980":1
        type: roundrobin
#END
--- error_code: 503
--- error_log
failed to fetch plugin config by id: 1



=== TEST 3: mix plugins & plugin_config_id
--- apisix_yaml
plugin_configs:
    -
        id: 1
        plugins:
            example-plugin:
                i: 1
            response-rewrite:
                body: "hello\n"
routes:
    - id: 1
      uri: /echo
      plugin_config_id: 1
      plugins:
        proxy-rewrite:
          headers:
            "in": "out"
        response-rewrite:
          body: "world\n"
      upstream:
        nodes:
          "127.0.0.1:1980":1
        type: roundrobin
#END
--- request
GET /echo
--- response_body
hello
--- response_headers
in: out
--- error_log eval
qr/conf_version: \d+#1,/
--- no_error_log
[error]



=== TEST 4: invalid plugin
--- apisix_yaml
plugin_configs:
    -
        id: 1
        plugins:
            example-plugin:
                skey: "s"
            response-rewrite:
                body: "hello\n"
routes:
    - id: 1
      uri: /hello
      plugin_config_id: 1
      upstream:
        nodes:
          "127.0.0.1:1980":1
        type: roundrobin
#END
--- error_code: 503
--- error_log
failed to check the configuration of plugin example-plugin
failed to fetch plugin config by id: 1
